class_name OcgReferenceSession
extends RefCounted

## Stateful Linux development session over nonblocking pipes to ONE native core.
## Fixture-only: not a drop-in EngineSession, not production-board selectable.
## start_fixture(), poll(viewer), submit(player, prompt_id, {offer: index}), stop().
## start_newdoria_fixture() adds one authored Lua effect and viewer-filtered battle views.
## start_practice_deck() adds reviewed Normal Monsters, private hands and setting.
## Production decks, arbitrary scripts and the full core protocol remain unsupported.

const MAX_PACKET_BYTES := 16384
const RESPONSE_TIMEOUT_MS := 11000
const ALLOWED_CHOICES := ["normal_summon", "choose_zone", "end_turn", "shuffle_hand", "discard"]
const PRACTICE_CHOICES := ["set_monster", "reposition", "choose_position"]
const PRACTICE_CODES := [7459013, 11091375, 21615956, 37265642, 43096270, 90582719]
const POOL_PATH := "res://Data/reference_cards/native_pool.json"
const BATTLE_CHOICES := ["battle_phase", "attack", "select_monster", "chain_effect", "pass_chain", "main_two"]

var _owner := OS.get_thread_caller_id()
var _pid := -1
var _child_live := false
var _stdio: FileAccess
var _stderr: FileAccess
var _buffer := PackedByteArray()
var _outboxes: Array = [[], []]
var _revision := ""
var _started := false
var _terminal := false
var _ready := false
var _pending := false
var _deadline := 0
var _last_error := ""
var _over_viewers: Array = []
var _terminal_reports: Array = []
var _real_cards := false
var _practice_profile := ""
var _pool_digest := ""


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# Do not call script methods on self during PREDELETE (see EngineSession).
	if _child_live and _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _stdio != null:
		_stdio.close()
	if _stderr != null:
		_stderr.close()


func start_fixture(seed: int = 42) -> bool:
	return _start(seed, false)


func start_newdoria_fixture(seed: int = 42) -> bool:
	return _start(seed, true)


func start_practice_deck(profile: String = "mixed", seed: int = 42) -> bool:
	if not profile in ["mixed", "dragons"]:
		_last_error = "Unsupported practice deck profile."
		return false
	return _start(seed, true, profile)


func _start(seed: int, real_cards: bool, practice_profile: String = "") -> bool:
	if OS.get_thread_caller_id() != _owner or _started or _terminal:
		return false
	if seed < 0 or seed > 4294967295 or not OcgCoreDiagnostic.is_available():
		_last_error = "A built Linux core and uint32 seed are required."
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(OcgCoreDiagnostic.LOCK_PATH)) != OK:
		_last_error = "Cannot read core manifest."
		return false
	if not parser.data is Dictionary or not parser.data.get("core") is Dictionary:
		_last_error = "Invalid core manifest."
		return false
	_revision = str(parser.data.core.get("revision", ""))
	if _revision.length() != 40:
		_last_error = "Invalid pinned core revision."
		return false
	_real_cards = real_cards
	_practice_profile = practice_profile
	var arguments := PackedStringArray(["--newdoria-session" if real_cards else "--session", "--seed", str(seed)])
	if not practice_profile.is_empty():
		_pool_digest = FileAccess.get_sha256(POOL_PATH)
		if _pool_digest.length() != 64:
			_last_error = "Cannot read the approved native practice pool."
			return false
		arguments = PackedStringArray(["--practice-session", "--seed", str(seed), "--deck", practice_profile])
	var process := OS.execute_with_pipe(ProjectSettings.globalize_path(OcgCoreDiagnostic.BINARY_PATH),
		arguments, false)
	if process.is_empty():
		_last_error = "Could not launch the isolated core process."
		return false
	_pid = int(process.pid)
	_child_live = true
	_stdio = process.stdio
	_stderr = process.stderr
	_started = true
	_pending = true
	_deadline = Time.get_ticks_msec() + RESPONSE_TIMEOUT_MS
	return true


func poll(viewer: int) -> Array:
	if OS.get_thread_caller_id() != _owner or viewer < 0 or viewer > 1:
		return []
	_pump()
	var messages: Array = _outboxes[viewer].duplicate(true)
	_outboxes[viewer] = []
	return messages


func submit(player: int, prompt_id: int, value: Variant) -> bool:
	if OS.get_thread_caller_id() != _owner or not is_running() or _pending or not _ready or not _over_viewers.is_empty():
		return false
	if player < 0 or player > 1 or prompt_id < 1 or prompt_id > 4294967295:
		return false
	if not value is Dictionary or value.size() != 1 or not value.get("offer") is int:
		return false
	var index: int = value.offer
	if index < 0 or index > 4294967295:
		return false
	# Exactly one short request may be in flight, so it fits within PIPE_BUF.
	_stdio.store_string("ANSWER %d %d %d\n" % [player, prompt_id, index])
	if _stdio.get_error() != OK:
		_fail("Could not write to the native core pipe.")
		return false
	_pending = true
	_deadline = Time.get_ticks_msec() + RESPONSE_TIMEOUT_MS
	return true


func stop() -> void:
	if OS.get_thread_caller_id() != _owner or _terminal:
		return
	_terminal = true
	_pending = false
	# A cooperative STOP normally exits immediately; cap shutdown time if broken.
	if _child_live and _pid > 0:
		_stdio.store_string("STOP\n")
		var deadline := Time.get_ticks_msec() + 250
		while Time.get_ticks_msec() < deadline:
			_child_live = OS.is_process_running(_pid)
			if not _child_live:
				break
			OS.delay_usec(1000)
	_close_process()
	_buffer.clear()
	_outboxes = [[{"type": "stopped", "player": -1}], [{"type": "stopped", "player": -1}]]


func is_running() -> bool:
	return _started and not _terminal


func process_id() -> int:
	return _pid


func last_error() -> String:
	return _last_error


func _pump() -> void:
	if not _started or _terminal:
		return
	if not _drain_output():
		return
	if not OS.is_process_running(_pid):
		_child_live = false
		var exit_code := OS.get_process_exit_code(_pid)
		# The child can write/exit between our last EAGAIN and this liveness
		# check. Drain the now-closed pipes once more before judging completion.
		if not _drain_output():
			return
		if _over_viewers.size() == 2 and _buffer.is_empty() and exit_code == 0:
			for report in _terminal_reports:
				_outboxes[int(report.player)].append(report.duplicate(true))
			_terminal = true
			_close_process()
		else:
			_fail("Native core exited before a clean complete result (exit %d)." % exit_code)
	elif _pending and Time.get_ticks_msec() > _deadline:
		_fail("Native core response timed out.")


func _drain_output() -> bool:
	# Nonblocking FileAccess reads return immediately. Keep partial JSON lines
	# across frames and cap work/output so a corrupted child cannot freeze the UI.
	for _iteration in 8:
		var bytes := _stdio.get_buffer(4096)
		if bytes.is_empty():
			break
		_buffer.append_array(bytes)
		if _buffer.size() > MAX_PACKET_BYTES:
			_fail("Native session packet exceeded the limit.")
			return false
		var newline := _buffer.find(10)
		while newline >= 0:
			var line := _buffer.slice(0, newline).get_string_from_utf8()
			_buffer = _buffer.slice(newline + 1)
			if not _accept_line(line):
				return false
			newline = _buffer.find(10)
	var errors := _stderr.get_buffer(4096)
	if not errors.is_empty():
		_fail("Native core stderr: %s" % errors.get_string_from_utf8().left(512))
		return false
	return true


func _accept_line(line: String) -> bool:
	var parser := JSON.new()
	if parser.parse(line) != OK or not parser.data is Dictionary:
		_fail("Native session returned malformed JSON.")
		return false
	var message: Dictionary = parser.data
	if message.get("schema_version") != 1 or message.get("core_revision") != _revision or typeof(message.get("fixture_only")) != TYPE_BOOL or message.fixture_only != true:
		_fail("Native session schema, core revision or fixture boundary mismatch.")
		return false
	var kind := str(message.get("type", ""))
	if not _over_viewers.is_empty() and kind != "over":
		_fail("Native session resumed messages after terminal processing began.")
		return false
	var allowed := ["schema_version", "core_revision", "fixture_only", "type", "player"]
	match kind:
		"ready":
			allowed.append("capabilities")
			if not _practice_profile.is_empty(): allowed.append_array(["pool_sha256", "deck_profile"])
		"prompt": allowed.append_array(["prompt_id", "mode", "offers", "view"])
		"rejected": allowed.append_array(["prompt_id", "reason"])
		"over": allowed.append_array(["winner", "reason_code", "view"])
		_: allowed = []
	if message.size() != allowed.size():
		_fail("Native message contains unknown or missing fields.")
		return false
	for key in message:
		if not key in allowed:
			_fail("Native message contains an unapproved field.")
			return false
	if kind == "ready":
		var capabilities := ["normal_summon", "choose_zone", "end_turn", "shuffle_hand", "discard", "deck_out"]
		if _real_cards:
			capabilities.append_array(BATTLE_CHOICES)
			capabilities.append("life_point_win")
		if not _practice_profile.is_empty():
			capabilities.append_array(PRACTICE_CHOICES)
			if message.get("pool_sha256") != _pool_digest or message.get("deck_profile") != _practice_profile:
				_fail("Native pool/profile differs from the selected approved metadata; rebuild the binary.")
				return false
		if _ready or message.get("player") != -1 or message.get("capabilities") != capabilities:
			_fail("Native session capabilities mismatch.")
			return false
		_ready = true
		return true
	if not _ready or not _whole_number(message.get("player"), 0, 1):
		_fail("Native session message has no valid player.")
		return false
	var player := int(message.player)
	if kind in ["prompt", "over"] and not _valid_view(message.get("view"), _real_cards, player, not _practice_profile.is_empty()):
		_fail("Native snapshot does not match the selected fixture shape.")
		return false
	if kind in ["prompt", "rejected"]:
		if not _whole_number(message.get("prompt_id"), 1, 4294967295):
			_fail("Native session prompt id is invalid.")
			return false
		message.prompt_id = int(message.prompt_id)
	if kind == "prompt":
		if not message.get("mode") in ["ACTION", "DECISION"] or not message.get("offers") is Array or message.offers.is_empty() or message.offers.size() > 64:
			_fail("Native session prompt shape is invalid.")
			return false
		for offer in message.offers:
			if not offer is Dictionary or offer.size() != 2 or not offer.get("label") is String:
				_fail("Native session offered an unsupported action.")
				return false
			if not offer.get("kind") in ALLOWED_CHOICES and not (_real_cards and offer.get("kind") in BATTLE_CHOICES) and not (not _practice_profile.is_empty() and offer.get("kind") in PRACTICE_CHOICES):
				_fail("Native session action exceeds selected fixture capabilities.")
				return false
	elif kind == "rejected":
		if not message.get("reason") in ["that is not the prompt open for you", "invalid choice index"]:
			_fail("Native rejection is malformed.")
			return false
	elif kind == "over":
		if player in _over_viewers or not _whole_number(message.get("winner"), 0, 2) or not (message.get("reason_code") == 2 or (_real_cards and message.get("reason_code") == 1)):
			_fail("Native result is outside the selected fixture outcomes.")
			return false
		if not _terminal_reports.is_empty():
			var previous: Dictionary = _terminal_reports[0]
			if message.winner != previous.winner or message.reason_code != previous.reason_code or not _matching_terminal_views(message.view, previous.view, _real_cards, not _practice_profile.is_empty()):
				_fail("Native terminal reports disagree between players.")
				return false
		_over_viewers.append(player)
		_terminal_reports.append(message.duplicate(true))
		_pending = true
		if _over_viewers.size() == 1:
			_deadline = Time.get_ticks_msec() + 1000
		return true
	else:
		_fail("Unsupported native session message type.")
		return false
	message.player = player
	_outboxes[player].append(message.duplicate(true))
	_pending = false
	return true


static func _valid_view(value: Variant, real_cards: bool = false, viewer: int = -1, practice: bool = false) -> bool:
	if not value is Dictionary or value.size() != (5 if real_cards else 4):
		return false
	if real_cards and value.get("viewer") != viewer:
		return false
	if not _whole_number(value.get("turn_player"), 0, 1) or not _whole_number(value.get("turn_number"), 1, 256):
		return false
	var phases := [1, 2, 4, 8, 16, 32, 64, 128, 256, 512] if real_cards else [1, 2, 4, 512]
	if not _whole_number(value.get("phase"), 1, 512) or not int(value.phase) in phases:
		return false
	if not value.get("players") is Array or value.players.size() != 2:
		return false
	for pid in 2:
		var player: Variant = value.players[pid]
		if not player is Dictionary or player.size() != (7 if practice else (6 if real_cards else 4)):
			return false
		for key in ["deck_count", "hand_count", "monster_count", "graveyard_count"]:
			var maximum := 5 if key == "monster_count" else (41 if real_cards and not practice and key == "graveyard_count" else 40)
			if not _whole_number(player.get(key), 0, maximum):
				return false
		if real_cards:
			if not _whole_number(player.get("life_points"), 0, 100000) or not player.get("monsters") is Array or player.monsters.size() != 5:
				return false
			var occupied := 0
			for slot in 5:
				var card: Variant = player.monsters[slot]
				if card == null:
					continue
				occupied += 1
				if not card is Dictionary or card.get("slot") != slot or typeof(card.get("known")) != TYPE_BOOL:
					return false
				if not _whole_number(card.get("position"), 1, 8) or not int(card.position) in [1, 2, 4, 8]:
					return false
				var should_know := pid == viewer or int(card.position) in [1, 4]
				if card.known != should_know or card.size() != (6 if should_know else 3):
					return false
				if should_know and (not _whole_number(card.get("code"), 1, 4294967295) or not _whole_number(card.get("attack"), -1, 100000) or not _whole_number(card.get("defense"), -1, 100000)):
					return false
				if practice and should_know and not int(card.code) in PRACTICE_CODES:
					return false
			if practice:
				if not player.get("hand") is Array or player.hand.size() != (int(player.hand_count) if pid == viewer else 0):
					return false
				for slot in player.hand.size():
					var card: Variant = player.hand[slot]
					if not card is Dictionary or card.size() != 4 or not _whole_number(card.get("slot"), slot, slot):
						return false
					if not _whole_number(card.get("code"), 1, 4294967295) or not int(card.code) in PRACTICE_CODES or not _whole_number(card.get("attack"), 0, 100000) or not _whole_number(card.get("defense"), 0, 100000):
						return false
			if occupied != player.monster_count:
				return false
	return true


static func _matching_terminal_views(a: Dictionary, b: Dictionary, real_cards: bool, practice: bool = false) -> bool:
	if not real_cards:
		return a == b
	var copies := [a.duplicate(true), b.duplicate(true)]
	for value in copies:
		value.erase("viewer")
		for player in value.players:
			if practice: player.hand = []
			for slot in 5:
				var card: Variant = player.monsters[slot]
				if card != null and int(card.position) in [2, 8]:
					player.monsters[slot] = {"slot": slot, "position": card.position}
	return copies[0] == copies[1]


static func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and value >= minimum and value <= maximum and value == floor(value)


func _fail(reason: String) -> void:
	_last_error = reason
	_terminal = true
	_pending = false
	_close_process()
	_buffer.clear()
	for viewer in [0, 1]:
		_outboxes[viewer].append({"type": "error", "player": -1, "reason": reason})


func _close_process() -> void:
	if _child_live and _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_child_live = false
	_pid = -1
	if _stdio != null:
		_stdio.close()
		_stdio = null
	if _stderr != null:
		_stderr.close()
		_stderr = null
