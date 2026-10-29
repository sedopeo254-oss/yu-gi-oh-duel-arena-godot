extends Control

## Opt-in native-core lab. Never selected by the production board or main scene.
var session: OcgReferenceSession
var current: Dictionary = {}
var viewer := -1
var covered := true
var finished := false
var status_line := "Starting native core…"
var _names: Dictionary = {}
var _status: Label
var _content: VBoxContainer
var _field: VBoxContainer
var _choices: GridContainer
var _cover: VBoxContainer
var _handoff: Label
var _guide: Label
var _pending_prompt: Dictionary = {}


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/reference_cards/newdoria_battle.json"))
	if data is Dictionary:
		for card in data.get("cards", []): _names[int(card.code)] = str(card.name)
	_build_ui()
	start_new_duel()


func _exit_tree() -> void:
	if session != null: session.stop()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cover_board()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if session == null: return
	for player in [0, 1]:
		for message in session.poll(player):
			match message.type:
				"prompt":
					_pending_prompt = {}
					current = message
					if viewer != player:
						viewer = player
						cover_board()
					status_line = "Player %d · Turn %d · %s" % [player + 1, int(message.view.turn_number), _phase(int(message.view.phase))]
					_render()
				"rejected":
					current = _pending_prompt
					_pending_prompt = {}
					status_line = "Core rejected the choice. Choose again."
					_render()
				"over":
					# Both reports are delivered only after a consistent clean native exit.
					if not finished and (viewer == player or viewer < 0):
						finished = true
						current = {}
						_pending_prompt = {}
						status_line = "PLAYER %d WINS · %s" % [int(message.winner) + 1, "LP reached zero" if int(message.reason_code) == 1 else "Deck exhausted"]
						_render_view(message.view)
						_clear(_choices)
						_status.text = status_line
				"error":
					current = {}
					_pending_prompt = {}
					finished = true
					status_line = "Native session stopped: " + str(message.get("reason", session.last_error()))
					_status.text = status_line
					_clear(_choices)
					cover_board()


func start_new_duel() -> void:
	if session != null: session.stop()
	session = OcgReferenceSession.new()
	current = {}
	_pending_prompt = {}
	viewer = -1
	finished = false
	_clear(_field)
	_clear(_choices)
	cover_board()
	status_line = "Starting native Newdoria fixture…"
	if not session.start_newdoria_fixture(42):
		status_line = "Build the optional Linux core first: python3 Tools/build_ocg_probe.py --fetch"
		finished = true
	_status.text = status_line


func close_session() -> void:
	if session != null: session.stop()
	current = {}
	_pending_prompt = {}
	finished = true
	status_line = "Session closed. No native duel process remains. Restart to play again."
	_status.text = status_line
	_clear(_field)
	_clear(_choices)
	cover_board()


func reveal_board() -> void:
	if viewer < 0 or finished: return
	covered = false
	_cover.hide()
	_content.show()


func cover_board() -> void:
	covered = true
	_content.hide()
	_cover.show()
	_handoff.text = "Pass to Player %d, then reveal the field." % (viewer + 1) if viewer >= 0 else "Waiting for a native session…"


func choose_offer(index: int) -> void:
	if covered or current.is_empty() or finished: return
	if index < 0 or index >= current.offers.size(): return
	var outgoing := current.duplicate(true)
	if not session.submit(int(outgoing.player), int(outgoing.prompt_id), {"offer": index}): return
	_pending_prompt = outgoing
	current = {}
	_clear(_choices)
	status_line = "Core is resolving the choice…"
	_status.text = status_line


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101927")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	var title := _label("NATIVE CORE · NEWDORIA BATTLE LAB", 32)
	column.add_child(title)
	var subtitle := _label("Isolated two-card experiment · Real Lua effect · Arranged opening field + synthetic Normal Monster decks", 18)
	column.add_child(subtitle)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	column.add_child(toolbar)
	_button(toolbar, "Restart fixture", start_new_duel)
	_button(toolbar, "Cover / Esc", cover_board)
	_button(toolbar, "Close native session", close_session)
	_status = _label(status_line, 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_cover = VBoxContainer.new()
	_cover.add_theme_constant_override("separation", 18)
	column.add_child(_cover)
	_handoff = _label("", 26)
	_cover.add_child(_handoff)
	_button(_cover, "Reveal for active player", reveal_board)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	column.add_child(_content)
	_guide = _label("", 19)
	_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_guide)
	_field = VBoxContainer.new()
	_field.add_theme_constant_override("separation", 14)
	_content.add_child(_field)
	_content.add_child(_label("CORE-OFFERED ACTIONS", 21))
	_choices = GridContainer.new()
	_choices.columns = 2
	_choices.add_theme_constant_override("h_separation", 12)
	_choices.add_theme_constant_override("v_separation", 8)
	_content.add_child(_choices)


func _render() -> void:
	_status.text = status_line
	_handoff.text = "Pass to Player %d, then reveal the field." % (viewer + 1)
	if current.is_empty(): return
	_render_view(current.view)
	_clear(_choices)
	for i in current.offers.size():
		_button(_choices, str(current.offers[i].label), choose_offer.bind(i))
	var turn := int(current.view.turn_number)
	_guide.text = "Try the effect: Player 1 ends turn. Player 2 enters Battle Phase, attacks Newdoria with The Portrait's Secret. Player 1 then selects the monster Newdoria will destroy."
	if turn >= 2 and int(current.view.players[0].graveyard_count) > 0:
		_guide.text = "Continue the native duel: summon and attack until LP reaches zero or a deck runs out. The initial Newdoria battle/effect has finished."
		if int(current.player) == 0 and not current.offers.is_empty() and current.offers[0].kind == "select_monster":
			_guide.text = "Newdoria reached the GY by battle. Its mandatory effect now requires Player 1 to select one offered field monster to destroy."


func _render_view(view: Dictionary) -> void:
	_clear(_field)
	for player in [1, 0]:
		var state: Dictionary = view.players[player]
		_field.add_child(_label("PLAYER %d   |   LP %d   ·   Deck %d   ·   Hand %d   ·   GY %d" % [player + 1, int(state.life_points), int(state.deck_count), int(state.hand_count), int(state.graveyard_count)], 22))
		var zones := HBoxContainer.new()
		zones.add_theme_constant_override("separation", 12)
		_field.add_child(zones)
		for slot in 5:
			var panel := PanelContainer.new()
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			panel.custom_minimum_size = Vector2(0, 120)
			var style := StyleBoxFlat.new()
			style.bg_color = Color("223249")
			style.set_content_margin_all(14)
			style.set_corner_radius_all(8)
			panel.add_theme_stylebox_override("panel", style)
			zones.add_child(panel)
			var card: Variant = state.monsters[slot]
			var text := "ZONE %d\n\n—" % (slot + 1)
			if card is Dictionary:
				text = "ZONE %d\n" % (slot + 1)
				if card.known:
					text += str(_names.get(int(card.code), "Reference Normal Monster"))
					text += "\nATK %d / DEF %d" % [int(card.attack), int(card.defense)]
				else: text += "Face-down monster"
				text += "\n" + ("Attack position" if int(card.position) in [1, 2] else "Defense position")
			var label := _label(text, 18)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			panel.add_child(label)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _phase(value: int) -> String:
	return str({1: "Draw Phase", 2: "Standby Phase", 4: "Main Phase 1", 8: "Battle Phase", 16: "Battle Step", 32: "Damage Step", 64: "Damage Calculation", 128: "Battle End", 256: "Main Phase 2", 512: "End Phase"}.get(value, "Phase %d" % value))
