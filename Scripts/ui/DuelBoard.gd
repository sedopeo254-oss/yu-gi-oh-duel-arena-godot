extends Control

## First playable 2D presentation. Only EngineSession owns play and legal choices.
## No rules or effects are reproduced here. Card art is an original vector placeholder.
@export var seed_value := 1001
@export var first_player := 0

const TEAL := Color("69d8ca")
const CORAL := Color("efa896")
const MUTED := Color("a7b6c6")
const CardFace = preload("res://Scripts/ui/ArenaCard.gd")
const Backdrop = preload("res://Scripts/ui/ArenaBackdrop.gd")
const AnimationDirector = preload("res://Scripts/presentation/CardAnimationDirector.gd")
const DuelSound = preload("res://Scripts/presentation/DuelAudio.gd")

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
var _animations: CardAnimationDirector
var _sound
var _audio_button: Button
var _audio_dialog: AcceptDialog
var _audio_toggle: CheckButton
var _audio_slider: HSlider
var _audio_value: Label
var _audio_note: Label
var _audio_column: VBoxContainer
var _audio_description: Label
var _native_dialog: ConfirmationDialog
var _native_unavailable: AcceptDialog
var _native_layer: CanvasLayer
var _native_lab: Control
var _native_returning := false
var _content: HBoxContainer
var _left_panel: VBoxContainer
var _right_panel: PanelContainer
var _middle_scroll: ScrollContainer
var _tabs: HBoxContainer
var _header: BoxContainer
var _descriptor: Label
var _footer: Label
var _margin: MarginContainer
var _cover_column: VBoxContainer
var _compact_layout := false
var _active_tab := 0
var _motion_button: CheckButton
var _toolbar: HFlowContainer
var _narrow_board := false
var _narrow_slot_width := 64.0
var _narrow_pile_width := 80.0
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
	get_window().size_changed.connect(_sync_window_layout)
	_sync_window_layout()
	start_new_duel()

func _exit_tree() -> void:
	if is_instance_valid(_native_lab): _native_lab.close_session()
	if session != null:
		session.stop()
		session = null

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cover_board()
		get_viewport().set_input_as_handled()

func start_new_duel() -> void:
	if is_instance_valid(_native_lab): return
	if _animations != null: _animations.reset()
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
	if str(message.get("type", "")) in ["prompt", "over"]:
		_animations.ingest(player, message.get("log", []), message.get("view", {}))
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
			status_line = _rejection_text if _rejection_text != "" else "Choose a legal move below. Tap a card to inspect it."
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
	_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	var header := BoxContainer.new()
	_header = header
	header.add_theme_constant_override("separation", 12)
	page.add_child(header)
	var brand := _label("DUEL ARENA", 26, Color("f2f1e9"))
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	_descriptor = _label("LOCAL DUEL  /  TWO PLAYERS", 12, MUTED)
	header.add_child(_descriptor)
	var toolbar := HFlowContainer.new()
	_toolbar = toolbar
	toolbar.add_theme_constant_override("h_separation", 8)
	header.add_child(toolbar)
	var cover_button := _button("Cover  [Esc]", cover_board)
	cover_button.custom_minimum_size.x = 130
	toolbar.add_child(cover_button)
	var motion_button := CheckButton.new()
	_motion_button = motion_button
	motion_button.text = "Reduce motion"
	motion_button.custom_minimum_size.y = 48
	motion_button.add_theme_font_size_override("font_size", 14)
	motion_button.tooltip_text = "Stop cosmetic movement and action sounds. All gameplay remains available."
	motion_button.toggled.connect(_set_reduced_motion)
	toolbar.add_child(motion_button)
	_audio_button = _button("Sound", _popup_audio_settings)
	_audio_button.custom_minimum_size.x = 120
	toolbar.add_child(_audio_button)
	var restart_button := _button("New duel", func(): _popup_confirmation(_restart_dialog))
	restart_button.custom_minimum_size.x = 110
	toolbar.add_child(restart_button)
	var native_button := _button("Core lab", _request_native_lab)
	native_button.custom_minimum_size.x = 120
	native_button.tooltip_text = "Optional Linux lab: Newdoria Lua scenario or six-card Normal Monster practice pool. Not the arena backend."
	toolbar.add_child(native_button)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	for tab in range(3):
		var button := _button(["Arena", "Moves", "Cards & feed"][tab], _select_tab.bind(tab))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tabs.add_child(button)
	page.add_child(_tabs)
	_content = HBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 18)
	page.add_child(_content)
	var left := VBoxContainer.new()
	_left_panel = left
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 14)
	_content.add_child(left)
	left.add_child(_label("CARD DETAILS", 13, TEAL))
	var inspect_scroll := ScrollContainer.new()
	inspect_scroll.custom_minimum_size.y = 200
	inspect_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(inspect_scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 12)
	inspect_scroll.add_child(_inspector)
	left.add_child(_label("DUEL FEED  /  YOUR VIEW", 13, TEAL))
	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size.y = 160
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(log_scroll)
	_log = _label("", 13, MUTED)
	_log.custom_minimum_size.x = 250
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_scroll.add_child(_log)
	var middle_scroll := ScrollContainer.new()
	_middle_scroll = middle_scroll
	middle_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_content.add_child(middle_scroll)
	_board = VBoxContainer.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_theme_constant_override("separation", 6)
	middle_scroll.add_child(_board)
	var right_panel := PanelContainer.new()
	_right_panel = right_panel
	right_panel.custom_minimum_size.x = 310
	right_panel.add_theme_stylebox_override("panel", _box(Color("102333"), Color("35505e"), 16))
	_content.add_child(right_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right_panel.add_child(right)
	_mode = _label("YOUR MOVE", 13, TEAL)
	right.add_child(_mode)
	_prompt = _label("", 22)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size.x = 270
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
	right.add_child(_label("Only legal actions are shown.\nPass the screen when the viewer changes.", 12, MUTED))
	_footer = _label("ORIGINAL ILLUSTRATIONS   /   77-CARD POOL   /   LOCAL PASS-AND-PLAY", 11, MUTED)
	page.add_child(_footer)
	_animations = AnimationDirector.new()
	add_child(_animations)
	_sound = DuelSound.new()
	add_child(_sound)
	_animations.animation_started.connect(_sound.play_cue)
	_animations.animation_finished.connect(_sound.finish_cue)
	_animations.playback_cancelled.connect(_sound.stop)
	_load_presentation_preferences()
	_build_cover()
	_build_audio_settings()
	_build_native_navigation()
	_restart_dialog = ConfirmationDialog.new()
	_restart_dialog.dialog_autowrap = true
	_restart_dialog.title = "Start a new duel?"
	_restart_dialog.dialog_text = "The current duel will end without saving. Start with a new shuffle?"
	_restart_dialog.confirmed.connect(func(): seed_value += 1; start_new_duel())
	add_child(_restart_dialog)
	_surrender_dialog = ConfirmationDialog.new()
	_surrender_dialog.dialog_autowrap = true
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
	_cover_column = column
	column.custom_minimum_size.x = 600
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	var emblem := _label("II", 66, TEAL)
	emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(emblem)
	var title := _label("DUEL ARENA", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_cover_title = _label("", 24, TEAL)
	_cover_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_cover_title)
	var note := _label("A private view for each player.\nPass the screen, then reveal when you are ready.", 16, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)
	_reveal = _button("I am ready — reveal my board", reveal_board)
	_reveal.custom_minimum_size.y = 62
	column.add_child(_reveal)
	column.add_child(_button("New duel", func(): _popup_confirmation(_restart_dialog)))
	column.add_child(_button("Sound settings", _popup_audio_settings))
	column.add_child(_button("Experimental core lab", _request_native_lab))


func _build_native_navigation() -> void:
	_native_dialog = ConfirmationDialog.new()
	_native_dialog.title = "Open experimental native lab?"
	_native_dialog.dialog_autowrap = true
	_native_dialog.dialog_text = "This ends your current arena duel without saving. Experimental modes: Newdoria Lua scenario or six Normal Monster practice pool. Copy limits are relaxed. Returning starts a new arena duel."
	_native_dialog.get_ok_button().text = "End duel and open lab"
	_native_dialog.confirmed.connect(_open_native_lab)
	add_child(_native_dialog)
	_native_unavailable = AcceptDialog.new()
	_native_unavailable.title = "Optional native core is not built"
	_native_unavailable.dialog_autowrap = true
	_native_unavailable.dialog_text = "Your arena duel is unchanged. The experimental lab requires Linux and an explicit local build: python3 Tools/build_ocg_probe.py --fetch. Nothing is downloaded or executed by this dialog."
	add_child(_native_unavailable)

func _native_core_available() -> bool:
	return OcgCoreDiagnostic.is_available()

func _request_native_lab() -> void:
	if is_instance_valid(_native_lab) or _native_dialog.visible or _native_unavailable.visible: return
	# Cover before displaying a modal: no private field or playing cue remains behind it.
	cover_board()
	_audio_dialog.hide()
	_restart_dialog.hide()
	_surrender_dialog.hide()
	if not _native_core_available():
		_native_unavailable.popup_centered(Vector2i(mini(500, int(get_viewport_rect().size.x) - 32), 220))
		return
	_popup_confirmation(_native_dialog)

func _open_native_lab() -> void:
	if is_instance_valid(_native_lab): return
	_native_dialog.hide()
	if not _native_core_available():
		_request_native_lab()
		return
	var packed := load("res://Scenes/dev/OcgBattleLab.tscn") as PackedScene
	if packed == null: return
	var lab := packed.instantiate() as Control
	if lab == null: return
	cover_board()
	_animations.reset()
	_sound.stop()
	if session != null: session.stop()
	session = null
	current = {}
	view = {}
	logs = [[], []]
	viewer = -1
	finished = false
	_reset_choice()
	_clear(_board)
	_clear(_choices)
	_clear(_inspector)
	_log.text = ""
	_native_returning = false
	_native_lab = lab
	_native_layer = CanvasLayer.new()
	_native_layer.layer = 20
	add_child(_native_layer)
	lab.return_requested.connect(_return_from_native_lab)
	_native_layer.add_child(lab)

func _return_from_native_lab() -> void:
	if not is_instance_valid(_native_lab) or _native_returning: return
	_native_returning = true
	_native_lab.close_session()
	_finish_native_return.call_deferred()

func _finish_native_return() -> void:
	if is_instance_valid(_native_layer): _native_layer.free()
	_native_lab = null
	_native_layer = null
	_native_returning = false
	seed_value += 1
	start_new_duel()

func _build_audio_settings() -> void:
	_audio_dialog = AcceptDialog.new()
	_audio_dialog.title = "Sound settings"
	add_child(_audio_dialog)
	var column := VBoxContainer.new()
	_audio_column = column
	column.custom_minimum_size.x = 252
	column.add_theme_constant_override("separation", 16)
	_audio_dialog.add_child(column)
	_audio_toggle = CheckButton.new()
	_audio_toggle.text = "Duel sound effects"
	_audio_toggle.custom_minimum_size.y = 48
	_audio_toggle.toggled.connect(_sound.set_enabled)
	column.add_child(_audio_toggle)
	column.add_child(_label("Effects volume", 16))
	var row := HBoxContainer.new()
	column.add_child(row)
	_audio_slider = HSlider.new()
	_audio_slider.min_value = 0
	_audio_slider.max_value = 100
	_audio_slider.step = 1
	_audio_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_slider.custom_minimum_size = Vector2(180, 48)
	_audio_slider.tooltip_text = "Sound effects volume. Zero is silent."
	_audio_slider.value_changed.connect(func(value): _sound.set_volume(value / 100.0))
	row.add_child(_audio_slider)
	_audio_value = _label("", 16)
	_audio_value.custom_minimum_size.x = 45
	row.add_child(_audio_value)
	var description := _label("Original anime-inspired synthesized cues.\nNot official anime recordings.\nReduce motion also silences action cues.", 14, MUTED)
	_audio_description = description
	description.size.x = 252
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	_audio_note = _label("", 13, MUTED)
	column.add_child(_audio_note)
	_sound.preferences_changed.connect(_refresh_audio_settings)
	_refresh_audio_settings()

func _popup_audio_settings() -> void:
	var width := mini(460, int(get_viewport_rect().size.x) - 32)
	# Wrapped text needs a real width before the first popup computes its minimum height.
	_audio_column.custom_minimum_size.x = width - 36
	_audio_description.size.x = width - 36
	_audio_dialog.popup_centered(Vector2i(width, 340))

func _refresh_audio_settings() -> void:
	_audio_toggle.set_pressed_no_signal(_sound.enabled)
	_audio_slider.set_value_no_signal(_sound.volume * 100.0)
	_audio_value.text = "%d%%" % roundi(_sound.volume * 100.0)
	_audio_button.text = "Sound %s" % (_audio_value.text if _sound.enabled and _sound.volume > 0.0 else "off")
	_audio_note.text = "Saved on this device." if _sound.last_save_error == OK else "Works now, but preferences could not be saved."

func _show_cover(title: String) -> void:
	_animations.conceal()
	_active_tab = 0
	_content.hide()
	_tabs.hide()
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
	_apply_layout()
	_render()

func _render() -> void:
	if handoff_required:
		var pid := int(current.get("player", viewer))
		_show_cover("Pass to %s" % _player_name(pid) if pid >= 0 else status_line)
		return
	_status.text = status_line
	_render_board()
	_animations.present(viewer)
	_animations.visible = not _compact_layout or _active_tab == 0
	_render_actions()
	if viewer >= 0:
		var recent: Array = (logs[viewer] as Array).slice(-10)
		_log.text = "\n\n".join(recent.map(func(line): return str(line).replace("_", " ").capitalize()))

func _render_board() -> void:
	_animations.begin_layout()
	_clear(_board)
	if view.is_empty(): return
	var players: Array = view.get("players", [])
	if players.size() != 2: return
	var own: Dictionary = players[viewer]
	var opponent: Dictionary = players[1 - viewer]
	_board.add_child(_player_header(opponent, CORAL, false))
	var backs := HFlowContainer.new()
	backs.alignment = FlowContainer.ALIGNMENT_CENTER
	for card in opponent.get("hand", []):
		var face := CardFace.new()
		face.configure(card, CORAL, true, _category(card))
		face.custom_minimum_size = Vector2(26, 36) if bool(card.get("hidden", true)) else Vector2(90, 100)
		face.disabled = bool(card.get("hidden", true))
		if not face.disabled: face.pressed.connect(_inspect.bind(card))
		backs.add_child(face)
	_board.add_child(backs)
	_render_side(opponent, CORAL, true)
	var phases := HBoxContainer.new()
	phases.alignment = BoxContainer.ALIGNMENT_CENTER
	phases.add_theme_constant_override("separation", 6)
	phases.add_child(_label(("T%02d" if _narrow_board else "TURN %02d") % int(view.get("turn", 0)), 13, TEAL))
	var phase_labels := ["D", "S", "M1", "B", "M2", "E"] if _narrow_board else ["DRAW", "STANDBY", "MAIN 1", "BATTLE", "MAIN 2", "END"]
	for i in range(phase_labels.size()):
		var panel := PanelContainer.new()
		var active := int(view.get("phase", -1)) == i
		panel.add_theme_stylebox_override("panel", _box(Color("274d48") if active else Color("111f2d"),
			TEAL if active else Color("273546"), 7))
		panel.tooltip_text = ["Draw", "Standby", "Main 1", "Battle", "Main 2", "End"][i]
		panel.add_child(_label(("• " if active else "") + phase_labels[i], 11, Color("e4fff5") if active else MUTED))
		phases.add_child(panel)
	_board.add_child(phases)
	var chain: Array = view.get("chain", [])
	if not chain.is_empty():
		_board.add_child(_label("CHAIN  /  %d link(s) waiting to resolve" % chain.size(), 13, CORAL))
	_render_side(own, TEAL, false)
	_board.add_child(_player_header(own, TEAL, true))
	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size.y = 154
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_board.add_child(hand_scroll)
	var hand := HBoxContainer.new()
	hand.add_theme_constant_override("separation", 10)
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_scroll.add_child(hand)
	for card in own.get("hand", []): hand.add_child(_card(card, TEAL, false))

func _player_header(player: Dictionary, color: Color, own: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("122735"), Color(color, 0.30), 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	var is_turn := int(view.get("turn_player", -1)) == int(player.get("id", -2))
	var title := _label(("YOU" if own else "OPPONENT") + ("  ·  TURN" if is_turn else "") + "  /  " + str(player.get("name", "")), 13, color)
	title.clip_text = true
	labels.add_child(title)
	var deck_name := _label(str(player.get("deck_name", "")), 11, MUTED)
	deck_name.clip_text = true
	labels.add_child(deck_name)
	var life := VBoxContainer.new()
	life.custom_minimum_size.x = 110 if _narrow_board else 145
	row.add_child(life)
	var points := _label("%s  LP" % str(player.get("life_points", 0)), 21 if _narrow_board else 25, Color("f1f4ed"))
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	life.add_child(points)
	var meter := ProgressBar.new()
	meter.custom_minimum_size.y = 4
	meter.show_percentage = false
	meter.max_value = maxf(8000, float(player.get("life_points", 0)))
	meter.value = float(player.get("life_points", 0))
	meter.add_theme_stylebox_override("background", _box(Color("081923"), Color("081923"), 0))
	meter.add_theme_stylebox_override("fill", _box(color, color, 0))
	life.add_child(meter)
	return panel

func _render_side(player: Dictionary, color: Color, opposing: bool) -> void:
	var side := BoxContainer.new()
	side.vertical = _narrow_board
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	_board.add_child(side)
	var support := BoxContainer.new()
	support.vertical = not _narrow_board
	support.alignment = BoxContainer.ALIGNMENT_CENTER
	support.add_theme_constant_override("separation", 8)
	side.add_child(support)
	var field := _zone(player.get("field_zone"), "FIELD", color)
	if _narrow_board and not player.get("field_zone") is Dictionary: field.custom_minimum_size = Vector2(_narrow_pile_width, 58)
	support.add_child(field)
	var deck_panel := PanelContainer.new()
	deck_panel.custom_minimum_size = Vector2(_narrow_pile_width, 58) if _narrow_board else Vector2(90, 100)
	deck_panel.add_theme_stylebox_override("panel", _box(Color("111b2a"), Color(color, 0.25), 8 if _narrow_board else 12))
	var deck_label := _label("DECK\n%d" % int(player.get("deck_count", 0)), 14 if _narrow_board else 18, color)
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
			var zone := _zone(data, ("MONSTER " if key == "monster_zones" else "SPELL / TRAP ") + str(i + 1), color)
			row.add_child(zone)
			if key == "monster_zones": _animations.register_zone(int(player.get("id", -1)), i, zone)
	var piles := BoxContainer.new()
	piles.vertical = not _narrow_board
	piles.add_theme_constant_override("separation", 8)
	if _narrow_board: support.add_child(piles)
	else: side.add_child(piles)
	for pile in ["graveyard", "banished"]:
		var entries: Array = player.get(pile, [])
		var pile_label := ("GY" if pile == "graveyard" else "BANISH") if _narrow_board else ("GRAVEYARD" if pile == "graveyard" else "BANISHED")
		var button := _button(pile_label + "\n%d" % entries.size(),
			_show_pile.bind(entries, pile.capitalize()))
		button.add_theme_font_size_override("font_size", 10)
		button.custom_minimum_size = Vector2(_narrow_pile_width, 58) if _narrow_board else Vector2(90, 100)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		piles.add_child(button)

func _zone(data, caption: String, color: Color) -> Control:
	if data is Dictionary: return _card(data, color, true)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_narrow_slot_width, 96) if _narrow_board else Vector2(90, 100)
	panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.17, 0.22, 0.70), Color(color, 0.26), 5))
	var zone_caption := caption.replace(" ", "\n") if caption.begins_with("MONSTER") else caption.replace("SPELL / TRAP ", "SPELL / TRAP\n")
	if _narrow_board: zone_caption = zone_caption.replace("SPELL / TRAP", "S / T")
	if _narrow_slot_width < 55 and _narrow_board: zone_caption = zone_caption.replace("MONSTER", "M")
	panel.tooltip_text = caption
	var label := _label(zone_caption, 9 if _narrow_board else 10, Color(color, 0.75))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel

func _card(data: Dictionary, color: Color, compact: bool) -> Control:
	var face := CardFace.new()
	face.configure(data, color, compact, _category(data))
	if compact and _narrow_board: face.custom_minimum_size = Vector2(_narrow_slot_width, 96)
	face.pressed.connect(_inspect.bind(data))
	return face

func _inspect(data: Dictionary) -> void:
	if handoff_required: return
	_clear(_inspector)
	if _compact_layout: _select_tab(2)
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
	if _compact_layout: _select_tab(2)
	_inspector.add_child(_label(title, 24))
	if entries.is_empty(): _inspector.add_child(_label("No cards here yet.", 16, MUTED))
	for entry in entries:
		_inspector.add_child(_button(_card_name(int(entry.get("id", -1))), _inspect.bind(entry)))

func _render_actions() -> void:
	_clear(_choices)
	(_tabs.get_child(1) as Button).text = "Moves" if current.is_empty() else "Moves •"
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
		_popup_confirmation(_surrender_dialog)
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
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("dce9f2"))
	button.add_theme_stylebox_override("normal", _box(Color("17283b"), Color("2e4459"), 10))
	button.add_theme_stylebox_override("hover", _box(Color("234253"), TEAL, 10))
	button.add_theme_stylebox_override("pressed", _box(Color("27544e"), TEAL, 10))
	button.add_theme_stylebox_override("disabled", _box(Color("14202d"), Color("273746"), 10))
	button.add_theme_color_override("font_disabled_color", Color("8c9caa"))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), TEAL, 10))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button

func _sync_window_layout() -> void:
	var window := get_window()
	# Preserve native-sized touch targets in small windows, cap the desktop design scale.
	var logical := Vector2i(mini(1920, window.size.x), mini(1080, window.size.y))
	if logical.x < 1 or logical.y < 1: return
	if window.content_scale_size != logical: window.content_scale_size = logical
	var narrow_before := _narrow_board
	_compact_layout = logical.x < 1450
	_narrow_board = logical.x < 700
	_narrow_slot_width = minf(64, maxf(48, (logical.x - 64.0) / 5.0))
	_narrow_pile_width = minf(80, maxf(60, (logical.x - 56.0) / 4.0))
	_right_panel.custom_minimum_size.x = 0 if _compact_layout else 310
	_prompt.custom_minimum_size.x = maxf(180, logical.x - 80) if _narrow_board else 270
	_toolbar.custom_minimum_size.x = 420 if not _narrow_board else 0
	_cover_column.custom_minimum_size.x = minf(600, logical.x - 48)
	_cover_column.add_theme_constant_override("separation", 10 if logical.y < 700 else 20)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 12 if _compact_layout else 20)
	_header.vertical = logical.x < 700
	_descriptor.visible = not _compact_layout
	_footer.visible = logical.y >= 700 and logical.x >= 700
	_apply_layout()
	if _audio_dialog != null and _audio_dialog.visible: _popup_audio_settings()
	if _native_dialog != null and _native_dialog.visible: _popup_confirmation(_native_dialog)
	if _native_unavailable != null and _native_unavailable.visible:
		_native_unavailable.popup_centered(Vector2i(mini(500, logical.x - 32), 220))
	if (narrow_before != _narrow_board or _narrow_board) and not handoff_required: _render_board()

func _select_tab(index: int) -> void:
	_active_tab = clampi(index, 0, 2)
	_apply_layout()

func _apply_layout() -> void:
	_tabs.visible = _compact_layout and not handoff_required
	_left_panel.visible = not _compact_layout or _active_tab == 2
	_middle_scroll.visible = not _compact_layout or _active_tab == 0
	_right_panel.visible = not _compact_layout or _active_tab == 1
	_left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact_layout else Control.SIZE_FILL
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact_layout else Control.SIZE_FILL
	if _animations != null:
		_animations.visible = not handoff_required and (not _compact_layout or _active_tab == 0)
	for i in range(_tabs.get_child_count()):
		var button := _tabs.get_child(i) as Button
		button.add_theme_stylebox_override("normal", _box(Color("234b47") if i == _active_tab else Color("17283b"), TEAL if i == _active_tab else Color("2e4459"), 10))

func _popup_confirmation(dialog: ConfirmationDialog) -> void:
	dialog.dialog_autowrap = true
	dialog.popup_centered(Vector2i(mini(500, int(get_viewport_rect().size.x) - 32), 180))

func _load_presentation_preferences() -> void:
	var preferences := ConfigFile.new()
	if preferences.load("user://presentation.cfg") != OK: return
	var reduced := bool(preferences.get_value("accessibility", "reduced_motion", false))
	_motion_button.set_pressed_no_signal(reduced)
	_animations.set_reduced_motion(reduced)

func _set_reduced_motion(enabled: bool) -> void:
	_animations.set_reduced_motion(enabled)
	var preferences := ConfigFile.new()
	preferences.set_value("accessibility", "reduced_motion", enabled)
	var error := preferences.save("user://presentation.cfg")
	if error != OK: push_warning("Could not save the reduced-motion preference: %s" % error_string(error))
