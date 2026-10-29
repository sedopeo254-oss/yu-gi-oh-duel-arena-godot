extends Control

## First playable 2D presentation. Only EngineSession owns play and legal choices.
## No rules or effects are reproduced here. Card art is an original vector placeholder.
@export var seed_value := 1001
@export var first_player := 0

const TEAL := Color("5ad8cc")
const CORAL := Color("ed9c8d")
const MUTED := Color("8b9bad")
const CardFace = preload("res://Scripts/ui/ArenaCard.gd")
const Backdrop = preload("res://Scripts/ui/ArenaBackdrop.gd")

var session: EngineSession
var current: Dictionary = {}
var view: Dictionary = {}
var logs: Array = [[], []]
var status_line := "Preparing the duel"
var _rejection_text := ""
var main_thread_only := true
var viewer := -1
var handoff_required := true
var finished := false
var _catalog: Dictionary = {}
var _content: HBoxContainer
var _board: VBoxContainer
var _choices: VBoxContainer
var _prompt: Label
var _mode: Label
var _status: Label
var _log: Label
var _inspector: VBoxContainer
var _cover: PanelContainer
var _cover_title: Label
var _reveal: Button
var _restart_dialog: ConfirmationDialog
var _surrender_dialog: ConfirmationDialog
var _surrender_prompt := -1
var _surrender_offer := -1
var _pending_offer: Dictionary = {}
var _steps: Array = []
var _step_index := 0
var _picked: Array = []
var _answers: Dictionary = {}
var _decision := false

func _ready() -> void:
	_load_catalog()
	_build_layout()
	start_new_duel()

func _exit_tree() -> void:
	if session != null:
		session.stop()
		session = null

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cover_board()
		get_viewport().set_input_as_handled()

func start_new_duel() -> void:
	if session != null: session.stop()
	session = null
	current = {}
	view = {}
	logs = [[], []]
	_rejection_text = ""
	viewer = -1
	finished = false
	if _surrender_dialog != null: _surrender_dialog.hide()
	handoff_required = true
	_reset_choice()
	_clear(_inspector)
	_inspector.add_child(_label("Select a visible card\nto inspect its details.", 17, MUTED))
	var lists := DeckLists.load_two_real_decks()
	if not (lists["errors"] as Array).is_empty():
		status_line = "Deck loading failed: %s" % str(lists["errors"])
		_show_cover(status_line)
		return
	session = EngineSession.new()
	if not session.start_duel(lists["decks"], lists["names"], seed_value, first_player):
		status_line = "The session could not be started. Restart to retry."
		_show_cover(status_line)
		return
	status_line = "Waiting for the first player"
	_show_cover("Preparing your duel")
	_reveal.disabled = true

func _process(_delta: float) -> void:
	if session == null: return
	var changed := false
	for player in [0, 1]:
		for message in session.poll(player):
			_on_message(message)
			changed = true
	if changed: _render()

func _on_message(message: Dictionary) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): main_thread_only = false
	var player := int(message.get("player", -1))
	match str(message.get("type", "")):
		"prompt":
			current = message
			view = message.get("view", {})
			_append_log(player, message.get("log", []))
			_reset_choice()
			if player != viewer:
				_clear(_inspector)
				_inspector.add_child(_label("Select a visible card\nto inspect its details.", 17, MUTED))
				handoff_required = true
			status_line = _rejection_text if _rejection_text != "" else "Choose an action supplied by the rules engine."
		"rejected":
			_rejection_text = "Not accepted: %s" % str(message.get("reason", "Please try again."))
			status_line = _rejection_text
		"over":
			_append_log(player, message.get("log", []))
			if player == viewer or viewer == -1:
				view = message.get("view", {})
			current = {}
			finished = true
			status_line = "%s · %s" % [str(message.get("result", "Duel over")).replace("_", " "),
				str(message.get("end_reason", "")).replace("_", " ")]
		"error":
			current = {}
			status_line = "Session error: %s" % str(message.get("reason", "Unknown error"))
		"stopped":
			current = {}
			status_line = "Session stopped. Start a new duel to continue."

func _append_log(player: int, entries: Array) -> void:
	if player < 0: return
	for entry in entries:
		var data: Dictionary = entry.get("data", {})
		var name_text := str(data.get("card_name", "")) if data.get("card_name") != null else ""
		(logs[player] as Array).append("T%d  %s%s" % [int(entry.get("turn", 0)),
			str(entry.get("kind", "")), " · " + name_text if name_text != "" else ""])
	# Bound a long session's presentation history, independent of the authoritative replay.
	if (logs[player] as Array).size() > 240: logs[player] = (logs[player] as Array).slice(-240)

func _build_layout() -> void:
	var bg := Backdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 26)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var brand := _label("◇  DUEL ARENA", 30, Color("edf4f6"))
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	header.add_child(_label("LOCAL TWO-PLAYER   /   FIRST PLAYABLE", 13, MUTED))
	var cover_button := _button("Cover board  [Esc]", cover_board)
	cover_button.custom_minimum_size.x = 170
	header.add_child(cover_button)
	var restart_button := _button("New duel", func(): _restart_dialog.popup_centered(Vector2i(500, 180)))
	restart_button.custom_minimum_size.x = 110
	header.add_child(restart_button)
	_content = HBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 22)
	page.add_child(_content)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	left.add_theme_constant_override("separation", 14)
	_content.add_child(left)
	left.add_child(_label("CARD INTELLIGENCE", 13, TEAL))
	var inspect_scroll := ScrollContainer.new()
	inspect_scroll.custom_minimum_size.y = 490
	inspect_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(inspect_scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 12)
	inspect_scroll.add_child(_inspector)
	left.add_child(_label("DUEL FEED  /  YOUR VIEW", 13, TEAL))
	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size.y = 210
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(log_scroll)
	_log = _label("", 13, MUTED)
	_log.custom_minimum_size.x = 250
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_scroll.add_child(_log)
	var middle_scroll := ScrollContainer.new()
	middle_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(middle_scroll)
	_board = VBoxContainer.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_theme_constant_override("separation", 10)
	middle_scroll.add_child(_board)
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size.x = 330
	right_panel.add_theme_stylebox_override("panel", _box(Color("101c2b"), Color("25384b"), 16))
	_content.add_child(right_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right_panel.add_child(right)
	_mode = _label("YOUR MOVE", 13, TEAL)
	right.add_child(_mode)
	_prompt = _label("", 22)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size.x = 290
	right.add_child(_prompt)
	_status = _label("", 13, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	var choices_scroll := ScrollContainer.new()
	choices_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(choices_scroll)
	_choices = VBoxContainer.new()
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.add_theme_constant_override("separation", 8)
	choices_scroll.add_child(_choices)
	right.add_child(_label("Engine-enforced choices\nNo automated opponent in this build", 12, MUTED))
	page.add_child(_label("ORIGINAL VECTOR ART  ·  77-CARD ENGINE POOL  ·  UNOFFICIAL FAN PROJECT", 11, MUTED))
	_build_cover()
	_restart_dialog = ConfirmationDialog.new()
	_restart_dialog.title = "Start a new duel?"
	_restart_dialog.dialog_text = "The current duel will end without saving. Start with a new shuffle?"
	_restart_dialog.confirmed.connect(func(): seed_value += 1; start_new_duel())
	add_child(_restart_dialog)
	_surrender_dialog = ConfirmationDialog.new()
	_surrender_dialog.title = "Surrender this duel?"
	_surrender_dialog.dialog_text = "Your opponent will win. This cannot be undone."
	_surrender_dialog.confirmed.connect(func():
		if not current.is_empty() and int(current["prompt_id"]) == _surrender_prompt:
			_submit({"offer": _surrender_offer, "choices": {}}))
	add_child(_surrender_dialog)

func _build_cover() -> void:
	_cover = PanelContainer.new()
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.add_theme_stylebox_override("panel", _box(Color("09111e"), Color("09111e"), 0))
	add_child(_cover)
	var center := CenterContainer.new()
	_cover.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 600
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	var emblem := _label("◇", 90, TEAL)
	emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(emblem)
	var title := _label("DUEL ARENA", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_cover_title = _label("", 24, TEAL)
	_cover_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_cover_title)
	var note := _label("Pass the screen privately.\nReveal only when the named player is ready.", 18, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)
	_reveal = _button("I am ready — reveal my board", reveal_board)
	_reveal.custom_minimum_size.y = 62
	column.add_child(_reveal)
	column.add_child(_button("New duel", func(): _restart_dialog.popup_centered(Vector2i(500, 180))))

func _show_cover(title: String) -> void:
	_content.hide()
	_cover.show()
	_cover_title.text = title
	_reveal.disabled = current.is_empty() and view.is_empty()
	_reveal.grab_focus()

func cover_board() -> void:
	handoff_required = true
	_render()

func reveal_board() -> void:
	if current.is_empty() and view.is_empty(): return
	if not current.is_empty(): viewer = int(current["player"])
	handoff_required = false
	_cover.hide()
	_content.show()
	_render()

func _render() -> void:
	if handoff_required:
		var pid := int(current.get("player", viewer))
		_show_cover("Pass to %s" % _player_name(pid) if pid >= 0 else status_line)
		return
	_status.text = status_line
	_render_board()
	_render_actions()
	if viewer >= 0:
		var recent: Array = (logs[viewer] as Array).slice(-10)
		_log.text = "\n\n".join(recent.map(func(line): return str(line).replace("_", " ").capitalize()))

func _render_board() -> void:
	_clear(_board)
	if view.is_empty(): return
	var players: Array = view.get("players", [])
	if players.size() != 2: return
	var own: Dictionary = players[viewer]
	var opponent: Dictionary = players[1 - viewer]
	_board.add_child(_player_header(opponent, CORAL, false))
	var backs := HBoxContainer.new()
	backs.alignment = BoxContainer.ALIGNMENT_CENTER
	for card in opponent.get("hand", []):
		var face := CardFace.new()
		face.configure(card, CORAL, true, _category(card))
		face.custom_minimum_size = Vector2(32, 44) if bool(card.get("hidden", true)) else Vector2(100, 110)
		face.disabled = bool(card.get("hidden", true))
		if not face.disabled: face.pressed.connect(_inspect.bind(card))
		backs.add_child(face)
	_board.add_child(backs)
	_render_side(opponent, CORAL, true)
	var phases := HBoxContainer.new()
	phases.alignment = BoxContainer.ALIGNMENT_CENTER
	phases.add_theme_constant_override("separation", 12)
	phases.add_child(_label("TURN %02d" % int(view.get("turn", 0)), 14, TEAL))
	var phase_labels := ["DRAW", "STANDBY", "MAIN 1", "BATTLE", "MAIN 2", "END"]
	for i in range(phase_labels.size()):
		var panel := PanelContainer.new()
		var active := int(view.get("phase", -1)) == i
		panel.add_theme_stylebox_override("panel", _box(Color("23443f") if active else Color("111c29"),
			TEAL if active else Color("273546"), 7))
		panel.add_child(_label(phase_labels[i], 12, TEAL if active else MUTED))
		phases.add_child(panel)
	_board.add_child(phases)
	var chain: Array = view.get("chain", [])
	if not chain.is_empty():
		_board.add_child(_label("CHAIN  /  %d link(s) waiting to resolve" % chain.size(), 13, CORAL))
	_render_side(own, TEAL, false)
	_board.add_child(_player_header(own, TEAL, true))
	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size.y = 186
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_board.add_child(hand_scroll)
	var hand := HBoxContainer.new()
	hand.add_theme_constant_override("separation", 10)
	hand_scroll.add_child(hand)
	for card in own.get("hand", []): hand.add_child(_card(card, TEAL, false))

func _player_header(player: Dictionary, color: Color, own: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("13202e"), Color(color, 0.25), 10))
	var row := HBoxContainer.new()
	panel.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	labels.add_child(_label(("YOU  /  " if own else "OPPONENT  /  ") + str(player.get("name", "")), 15, color))
	labels.add_child(_label(str(player.get("deck_name", "")), 12, MUTED))
	row.add_child(_label("%s  LP" % str(player.get("life_points", 0)), 29, color))
	return panel

func _render_side(player: Dictionary, color: Color, opposing: bool) -> void:
	var side := HBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 12)
	_board.add_child(side)
	var support := VBoxContainer.new()
	support.add_theme_constant_override("separation", 8)
	side.add_child(support)
	support.add_child(_zone(player.get("field_zone"), "FIELD", color))
	var deck_panel := PanelContainer.new()
	deck_panel.custom_minimum_size = Vector2(100, 110)
	deck_panel.add_theme_stylebox_override("panel", _box(Color("111b2a"), Color(color, 0.25), 12))
	var deck_label := _label("◇\nDECK\n%d" % int(player.get("deck_count", 0)), 17, color)
	deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deck_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	deck_panel.add_child(deck_label)
	support.add_child(deck_panel)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	side.add_child(grid)
	var rows := ["spell_trap_zones", "monster_zones"] if opposing else ["monster_zones", "spell_trap_zones"]
	for key in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		grid.add_child(row)
		var cards: Array = player.get(key, [])
		for j in range(5):
			var i := 4 - j if opposing else j
			var data = cards[i] if i < cards.size() else null
			row.add_child(_zone(data, ("MONSTER " if key == "monster_zones" else "SPELL / TRAP ") + str(i + 1), color))
	var piles := VBoxContainer.new()
	piles.add_theme_constant_override("separation", 8)
	side.add_child(piles)
	for pile in ["graveyard", "banished"]:
		var entries: Array = player.get(pile, [])
		var button := _button(("GRAVEYARD" if pile == "graveyard" else "BANISHED") + "\n%d" % entries.size(),
			_show_pile.bind(entries, pile.capitalize()))
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size = Vector2(100, 110)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		piles.add_child(button)

func _zone(data, caption: String, color: Color) -> Control:
	if data is Dictionary: return _card(data, color, true)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(100, 110)
	panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.14, 0.20, 0.42), Color(color, 0.18), 6))
	var label := _label("◇\n" + caption, 10, Color(color, 0.45))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel

func _card(data: Dictionary, color: Color, compact: bool) -> Control:
	var face := CardFace.new()
	face.configure(data, color, compact, _category(data))
	face.pressed.connect(_inspect.bind(data))
	return face

func _inspect(data: Dictionary) -> void:
	if handoff_required: return
	_clear(_inspector)
	if bool(data.get("hidden", true)):
		_inspector.add_child(_label("Face-down card", 24))
		_inspector.add_child(_label("This card's identity is hidden\nfrom your current view.", 16, MUTED))
		return
	var face := CardFace.new()
	face.configure(data, TEAL, false, _category(data))
	face.custom_minimum_size = Vector2(240, 310)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector.add_child(face)
	var entry: Dictionary = _catalog.get(str(data.get("name", "")), {})
	var name_label := _label(str(data.get("name", "Card")), 23)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector.add_child(name_label)
	_inspector.add_child(_label(str(entry.get("icon", entry.get("race", entry.get("category", "")))), 14, TEAL))
	var text_label := _label(str(entry.get("text", "No printed description available.")), 16, Color("c6d0dc"))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size.x = 245
	_inspector.add_child(text_label)
	if bool(data.get("effects_negated", false)): _inspector.add_child(_label("EFFECTS NEGATED", 14, CORAL))
	if not (data.get("counters", {}) as Dictionary).is_empty():
		_inspector.add_child(_label("Counters: %s" % str(data["counters"]), 14, TEAL))

func _show_pile(entries: Array, title: String) -> void:
	if handoff_required: return
	_clear(_inspector)
	_inspector.add_child(_label(title, 24))
	if entries.is_empty(): _inspector.add_child(_label("No cards here yet.", 16, MUTED))
	for entry in entries:
		_inspector.add_child(_button(_card_name(int(entry.get("id", -1))), _inspect.bind(entry)))

func _render_actions() -> void:
	_clear(_choices)
	if current.is_empty():
		_mode.text = "DUEL COMPLETE" if finished else "RESOLVING"
		_prompt.text = "Duel complete" if finished else "Waiting for the engine…"
		if finished: _choices.add_child(_button("Play again", func(): seed_value += 1; start_new_duel()))
		return
	_mode.text = "%s  /  %s" % [_player_name(int(current["player"])).to_upper(), str(current["mode"])]
	_prompt.text = str(current.get("prompt", "Choose your move"))
	if not _steps.is_empty():
		_render_selection()
		return
	if str(current["mode"]) == EngineSession.MODE_DECISION:
		var request: Dictionary = current.get("request", {})
		if str(request.get("kind", "")) == "YES_NO":
			_choices.add_child(_button("Yes", _submit.bind(true)))
			_choices.add_child(_button("No", _submit.bind(false)))
		else:
			_decision = true
			var options: Array = request.get("options", [])
			_steps = [{"field": "decision", "title": str(request.get("prompt", "Select cards")),
				"values": range(options.size()), "labels": _decision_labels(request),
				"min": int(request.get("min_count", 1)), "max": int(request.get("max_count", 1)),
				"ordered": str(request.get("kind", "")) == "ORDER_TRIGGERS"}]
			_render_selection()
		return
	for offer in current.get("offers", []):
		var button := _button(_action_label(offer), _begin_offer.bind(offer))
		button.tooltip_text = str(offer.get("clause_text", ""))
		_choices.add_child(button)

func _action_label(offer: Dictionary) -> String:
	var caption := str(offer.get("label", offer.get("kind", "Action")))
	if int(offer.get("card_id", -1)) == -1: return caption
	var card = _find_card(view, int(offer["card_id"]))
	if card is Dictionary and not bool(card.get("hidden", true)):
		var card_name := str(card.get("name", ""))
		if card_name != "" and not caption.contains(card_name): caption += "\n" + card_name
	return caption

func _begin_offer(offer: Dictionary) -> void:
	if current.is_empty() or handoff_required: return
	if str(offer.get("kind", "")) == "SURRENDER":
		_surrender_prompt = int(current["prompt_id"])
		_surrender_offer = int(offer["index"])
		_surrender_dialog.popup_centered(Vector2i(500, 180))
		return
	_reset_choice()
	_pending_offer = offer
	if int(offer.get("tributes_required", 0)) > 0:
		var combinations: Array = offer.get("tribute_combinations", [])
		_steps.append({"field": "tribute_ids", "title": "Choose the tribute group", "values": combinations,
			"labels": combinations.map(func(ids): return " + ".join(ids.map(func(id): return _card_name(int(id))))),
			"min": 1, "max": 1, "unwrap": true})
	if str(offer.get("kind", "")) == "DECLARE_ATTACK":
		var targets: Array = (offer.get("attack_target_candidates", []) as Array).duplicate()
		if bool(offer.get("allows_direct_attack", false)): targets.append(-1)
		_steps.append({"field": "attack_target_id", "title": "Choose the attack target", "values": targets,
			"labels": targets.map(func(id): return "Direct attack" if int(id) == -1 else _card_name(int(id))),
			"min": 1, "max": 1, "unwrap": true})
	elif int(offer.get("target_max", 0)) > 0:
		var targets: Array = offer.get("target_candidates", [])
		_steps.append({"field": "target_ids", "title": "Choose target(s)", "values": targets,
			"labels": targets.map(func(id): return _card_name(int(id))),
			"min": int(offer.get("target_min", 0)), "max": int(offer.get("target_max", 1))})
	var positions: Array = offer.get("legal_positions", [])
	if positions.size() > 1:
		_steps.append({"field": "position", "title": "Choose battle position", "values": positions,
			"labels": positions.map(func(pos): return str(Enums.Position.keys()[int(pos)]).replace("_", " ").capitalize()),
			"min": 1, "max": 1, "unwrap": true})
	if _steps.is_empty(): _submit({"offer": int(offer["index"]), "choices": {}})
	else: _render_actions()

func _render_selection() -> void:
	_clear(_choices)
	var step: Dictionary = _steps[_step_index]
	var ordered := bool(step.get("ordered", false))
	_choices.add_child(_label(str(step.get("title", "Choose")), 18, TEAL))
	var summary := "%d selected · choose %d–%d" % [_picked.size(), int(step["min"]), int(step["max"])]
	if ordered: summary = "Click in the requested order (%d / %d)" % [_picked.size(), int(step["max"])]
	_choices.add_child(_label(summary, 13, MUTED))
	var values: Array = step["values"]
	var labels: Array = step["labels"]
	for i in range(values.size()):
		var picked_index := _picked.find(i)
		var prefix := ("%d. " % (picked_index + 1)) if ordered and picked_index >= 0 else ("✓  " if picked_index >= 0 else "○  ")
		var button := _button(prefix + str(labels[i]), _toggle_pick.bind(i))
		button.disabled = picked_index < 0 and _picked.size() >= int(step["max"])
		_choices.add_child(button)
	var confirm := _button("Confirm selection", _confirm_selection)
	confirm.disabled = _picked.size() < int(step["min"]) or _picked.size() > int(step["max"])
	_choices.add_child(confirm)
	_choices.add_child(_button("Clear selection", func(): _picked = []; _render_actions()))
	if not _decision: _choices.add_child(_button("Back to actions", func(): _reset_choice(); _render_actions()))

func _toggle_pick(index: int) -> void:
	if current.is_empty() or _steps.is_empty() or handoff_required: return
	if _picked.has(index): _picked.erase(index)
	elif _picked.size() < int((_steps[_step_index] as Dictionary)["max"]): _picked.append(index)
	_render_actions()

func _confirm_selection() -> void:
	if current.is_empty() or _steps.is_empty() or handoff_required: return
	var step: Dictionary = _steps[_step_index]
	if _picked.size() < int(step["min"]) or _picked.size() > int(step["max"]): return
	var values: Array = step["values"]
	var selected: Array = _picked.map(func(index): return values[index])
	if _decision:
		_submit(selected)
		return
	_answers[str(step["field"])] = selected[0] if bool(step.get("unwrap", false)) else selected
	_step_index += 1
	_picked = []
	if _step_index == _steps.size():
		_submit({"offer": int(_pending_offer["index"]), "choices": _answers.duplicate(true)})
	else: _render_actions()

func _submit(value) -> void:
	if session == null or current.is_empty() or handoff_required: return
	# Invalidate immediately; repeated clicks cannot answer the next question accidentally.
	var player := int(current["player"])
	var prompt_id := int(current["prompt_id"])
	current = {}
	_reset_choice()
	_rejection_text = ""
	status_line = "Resolving your choice…"
	session.submit(player, prompt_id, value)
	_render()

func _reset_choice() -> void:
	_pending_offer = {}
	_steps = []
	_step_index = 0
	_picked = []
	_answers = {}
	_decision = false

func _player_name(pid: int) -> String:
	for player in view.get("players", []):
		if int(player.get("id", -1)) == pid: return str(player.get("name", "Player %d" % (pid + 1)))
	return "Player %d" % (pid + 1)

func _card_name(id: int) -> String:
	var found = _find_card(view, id)
	if found is Dictionary:
		if not bool(found.get("hidden", true)): return str(found.get("name", "Card"))
		var zone := int(found.get("zone", -1))
		var index := int(found.get("zone_index", -1))
		return "Face-down %s%s" % ["monster" if zone == 2 else "card", " · zone %d" % (index + 1) if index >= 0 else ""]
	return "Offered card" # Never print an internal identity or infer a hidden name.

func _decision_labels(request: Dictionary) -> Array:
	var labels: Array = []
	var options: Array = request.get("options", [])
	for i in range(options.size()):
		var option = options[i]
		if str(request.get("kind", "")) == "CHOOSE_POSITION":
			labels.append(str(Enums.Position.keys()[int(option)]).replace("_", " ").capitalize())
		elif str(request.get("kind", "")) == "CHOOSE_ZONE":
			labels.append("Zone %d" % (int(option) + 1))
		elif (request.get("option_labels", []) as Array).size() == options.size() and str(request["option_labels"][i]) != "":
			labels.append(str(request["option_labels"][i]))
		else:
			labels.append(_option_name(option))
	return labels

func _option_name(option) -> String:
	if typeof(option) == TYPE_INT: return _card_name(int(option))
	if option is Dictionary: return str(option.get("label", option.get("card_name", option.get("effect_id", "Offered option"))))
	return str(option)

static func _find_card(value, id: int):
	if value is Dictionary:
		if value.has("hidden") and value.has("id") and int(value["id"]) == id: return value
		for key in value:
			var hit = _find_card(value[key], id)
			if hit != null: return hit
	elif value is Array:
		for item in value:
			var hit = _find_card(item, id)
			if hit != null: return hit
	return null

func _load_catalog() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://Data/cards/cards.json"))
	if parsed is Dictionary:
		for entry in parsed.get("cards", []): _catalog[str(entry.get("name", ""))] = entry

func _category(card: Dictionary) -> String:
	if bool(card.get("hidden", true)): return ""
	return str((_catalog.get(str(card.get("name", "")), {}) as Dictionary).get("category", ""))

static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

static func _label(text_value: String, font_size: int, color: Color = Color("e4ecf5")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

static func _box(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: box.set_content_margin(side, padding)
	return box

static func _button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 45
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("dce9f2"))
	button.add_theme_stylebox_override("normal", _box(Color("17283b"), Color("2e4459"), 10))
	button.add_theme_stylebox_override("hover", _box(Color("234253"), TEAL, 10))
	button.add_theme_stylebox_override("pressed", _box(Color("27544e"), TEAL, 10))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), TEAL, 10))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button
