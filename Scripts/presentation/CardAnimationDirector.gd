class_name CardAnimationDirector
extends Control

## Main-thread, viewer-projected presentation only. Consume delivered EngineSession logs,
## never a DuelEngine or GameState. Timelines are cosmetic and never gate legal input.
## The board may rebuild Controls freely: anchors are rebound by public field location.
signal animation_started(action: String, visible_name: String)
signal animation_finished(action: String, visible_name: String)
## Audio and any later cosmetic consumers must stop with the visible timeline.
signal playback_cancelled

const Registry = preload("res://Scripts/presentation/CardAnimationRegistry.gd")
const MAX_QUEUED := 32
var registry = Registry.new()
var reduced_motion := false
var active: Dictionary = {}
var active_viewer := -1
var played_counts: Dictionary = {}
var _elapsed := 0.0
var _clock := 0.0
var _covered := true
var _models: Array = [{}, {}]
var _pending: Array = [[], []]
var _queue: Array = []
var _anchors: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func reset() -> void:
	conceal()
	_models = [{}, {}]
	_pending = [[], []]
	_anchors.clear()
	played_counts.clear()
	_clock = 0.0

func conceal() -> void:
	# Cancel instead of pausing: no one can uncover the previous viewer's active effect.
	playback_cancelled.emit()
	_covered = true
	active_viewer = -1
	active.clear()
	_queue.clear()
	_elapsed = 0.0
	hide()
	queue_redraw()

func begin_layout() -> void:
	_anchors.clear()

func register_zone(player: int, index: int, control: Control, compact_card: bool = true) -> void:
	_anchors[_slot(player, index)] = {"control": weakref(control), "compact": compact_card}

func ingest(player: int, entries: Array, snapshot: Dictionary) -> void:
	if player not in [0, 1]: return
	var before: Dictionary = _models[player]
	var after := _monster_index(snapshot)
	var destroyed_ids: Array = []
	var flipped_ids: Array = []
	for entry in entries:
		if str(entry.get("kind", "")) == "CARD_DESTROYED":
			destroyed_ids.append(int(entry.get("data", {}).get("card_id", -1)))
		if str(entry.get("kind", "")) == "FLIP_SUMMON_SUCCEEDED":
			flipped_ids.append(int(entry.get("data", {}).get("card_id", -1)))
	# A fresh snapshot can conceal/remove a card while its old timeline is running.
	# Cancel stale identification immediately, not merely the next idle drawing.
	if active_viewer == player:
		if not active.is_empty() and not _still_public(active, after, destroyed_ids):
			active.clear()
			playback_cancelled.emit()
		_queue = _queue.filter(func(job): return _still_public(job, after, destroyed_ids))
	_pending[player] = _pending[player].filter(func(job): return _still_public(job, after, destroyed_ids))
	for entry in entries:
		var data: Dictionary = entry.get("data", {})
		var kind := str(entry.get("kind", ""))
		var action := ""
		var id := int(data.get("card_id", -1))
		match kind:
			"NORMAL_SUMMON_SUCCEEDED", "SPECIAL_SUMMON_SUCCEEDED", "FLIP_SUMMON_SUCCEEDED": action = "summon"
			"ATTACK_DECLARED":
				action = "attack"
				id = int(data.get("attacker_id", -1))
			"BATTLE_POSITION_CHANGED": action = "position"
			"CARD_DESTROYED": action = "destroy"
		if action.is_empty(): continue
		if action == "position" and flipped_ids.has(id): continue # One reveal, not position + summon.
		if not after.has(id) and not destroyed_ids.has(id): continue
		var card: Dictionary = after.get(id, before.get(id, {})).duplicate(true)
		if action == "destroy": card = (before.get(id, {}) as Dictionary).duplicate(true)
		# Unknown, private and now-hidden cards do not receive identifying artwork. Never join
		# historical public IDs to opaque hidden handles or infer a card from the deck list.
		if registry.profile_for(card) == null: continue
		if after.has(id) and registry.profile_for(after[id]) == null: continue
		if action == "destroy" and int(data.get("from_zone", -1)) != Enums.Zone.MONSTER_ZONE: continue
		if action == "position":
			var new_position := int(data.get("to", -1))
			if new_position not in [Enums.Position.FACE_UP_ATTACK, Enums.Position.FACE_UP_DEFENSE]: continue
			card["position"] = new_position
		var target: Dictionary = after.get(int(data.get("target_id", -1)), before.get(int(data.get("target_id", -1)), {}))
		(_pending[player] as Array).append({"action": action, "card": card,
			"target_slot": _card_slot(target) if not target.is_empty() else "",
			"target_id": int(data.get("target_id", -1))})
	# Keep bursts bounded; rules continue immediately, so old cosmetics may be skipped.
	if _pending[player].size() > MAX_QUEUED: _pending[player] = _pending[player].slice(-MAX_QUEUED)
	_models[player] = after

func present(player: int) -> void:
	if player not in [0, 1]: return
	if active_viewer != player:
		playback_cancelled.emit()
		active.clear()
		_queue.clear()
		_elapsed = 0.0
	active_viewer = player
	_covered = false
	_queue.append_array(_pending[player])
	_pending[player] = []
	if _queue.size() > MAX_QUEUED: _queue = _queue.slice(-MAX_QUEUED)
	if reduced_motion: skip()
	show()
	queue_redraw()

func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	if enabled: skip()
	queue_redraw()

func skip() -> void:
	playback_cancelled.emit()
	active.clear()
	_queue.clear()
	_pending = [[], []]
	_elapsed = 0.0
	queue_redraw()

func is_busy() -> bool:
	return not active.is_empty() or not _queue.is_empty()

func _process(delta: float) -> void:
	if _covered: return
	_clock += delta
	if not reduced_motion:
		if active.is_empty() and not _queue.is_empty():
			active = _queue.pop_front()
			_elapsed = 0.0
			var action := str(active["action"])
			played_counts[action] = int(played_counts.get(action, 0)) + 1
			animation_started.emit(action, str(active["card"].get("name", "")))
		if not active.is_empty():
			_elapsed += delta
			var profile = registry.profile_for(active["card"])
			if profile == null or _elapsed >= profile.duration(str(active["action"])):
				animation_finished.emit(str(active["action"]), str(active["card"].get("name", "")))
				active.clear()
	queue_redraw()

func _draw() -> void:
	if _covered or active_viewer not in [0, 1]: return
	var active_slot := _card_slot(active.get("card", {}))
	# Retain a public target at its former slot until its queued destruction starts.
	# Otherwise an already-resolved battle would make the lunge slash an empty zone.
	var ghosts := {}
	for job in _queue:
		if str(job["action"]) != "destroy": continue
		var ghost: Dictionary = job["card"]
		var slot := _card_slot(ghost)
		if slot == active_slot or ghosts.has(slot): continue
		ghosts[slot] = true
		_draw_card(ghost, "idle", 1.0, "")
	for card in (_models[active_viewer] as Dictionary).values():
		if ghosts.has(_card_slot(card)): continue
		if not active.is_empty() and _card_slot(card) == active_slot: continue
		_draw_card(card, "idle", 1.0, "")
	if not active.is_empty():
		var profile = registry.profile_for(active["card"])
		if profile != null:
			_draw_card(active["card"], str(active["action"]),
				clampf(_elapsed / maxf(0.01, profile.duration(str(active["action"]))), 0, 1), str(active["target_slot"]))

func _draw_card(card: Dictionary, action: String, progress: float, target_slot: String) -> void:
	var profile = registry.profile_for(card)
	if profile == null: return
	var rect := _anchor_rect(_card_slot(card))
	if not rect.has_area(): return
	var target_rect := _anchor_rect(target_slot)
	var target := target_rect.get_center() if target_rect.has_area() else rect.get_center() + Vector2(0, -110 if int(card.get("controller", -1)) == active_viewer else 110)
	profile.draw(self, rect, action, progress, 0.0 if reduced_motion else _clock,
		int(card.get("position", 0)) == Enums.Position.FACE_UP_DEFENSE, target)

func _anchor_rect(key: String) -> Rect2:
	if not _anchors.has(key): return Rect2()
	var control = _anchors[key]["control"].get_ref()
	if not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree(): return Rect2()
	var full: Rect2 = control.get_global_rect()
	var compact_card: bool = _anchors[key]["compact"]
	var art := Rect2(full.position + Vector2(11, 34), Vector2(maxf(1, full.size.x - 22), full.size.y * 0.31)) if compact_card else full
	# This overlay is outside the scroll container so slashes can cross slots. Do not
	# leave identifying actors floating over neighboring panels when scrolled offscreen.
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer and not ancestor.get_global_rect().encloses(art): return Rect2()
		ancestor = ancestor.get_parent()
	return Rect2(get_global_transform_with_canvas().affine_inverse() * art.position, art.size)

static func _slot(player: int, index: int) -> String:
	return "%d:%d" % [player, index]

static func _card_slot(card: Dictionary) -> String:
	return _slot(int(card.get("controller", -1)), int(card.get("zone_index", -1)))

static func _monster_index(snapshot: Dictionary) -> Dictionary:
	var result := {}
	for player in snapshot.get("players", []):
		var zones: Array = player.get("monster_zones", [])
		for i in range(zones.size()):
			if not zones[i] is Dictionary: continue
			var card: Dictionary = zones[i].duplicate(true)
			card["controller"] = int(player.get("id", -1))
			card["zone_index"] = i
			result[int(card.get("id", -1))] = card
	return result

func _still_public(job: Dictionary, after: Dictionary, destroyed_ids: Array) -> bool:
	var id := int(job.get("card", {}).get("id", -1))
	if destroyed_ids.has(id): return true
	if not after.has(id) or registry.profile_for(after[id]) == null: return false
	# A visible control/zone change does not authorize drawing at its obsolete slot.
	if _card_slot(after[id]) != _card_slot(job.get("card", {})): return false
	var target_id := int(job.get("target_id", -1))
	if str(job.get("action", "")) == "attack" and target_id != -1 and not destroyed_ids.has(target_id):
		if not after.has(target_id) or _card_slot(after[target_id]) != str(job.get("target_slot", "")): return false
	return true
