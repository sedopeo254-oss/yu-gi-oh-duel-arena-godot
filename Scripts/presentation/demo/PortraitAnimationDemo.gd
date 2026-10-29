extends Control

## F6 / explicit scene only. Original cinematic presentation of an arranged engine fixture.
const Scenario = preload("res://Scripts/presentation/demo/PortraitAnimationScenario.gd")
const Backdrop = preload("res://Scripts/presentation/demo/PortraitStageBackdrop.gd")
const Soundscape = preload("res://Scripts/presentation/demo/PortraitSoundscape.gd")
const ACCENT := Color("d09a91")
const INK := Color("e8ddd3")
const MUTED := Color("867d87")
const STEP_NAMES := ["AWAKENING", "RETREAT", "RE-EMERGENCE", "THE STRIKE", "UNRAVELING"]
const STEP_DESCRIPTIONS := ["Something stirs behind the canvas.", "The hand withdraws. The frame turns away.",
	"The veil lifts. A presence returns.", "The frame surges. Three claws cut the air.", "Old wood fractures. The canvas gives way."]
var scenario
var director: CardAnimationDirector
var caption: Label
var detail: Label
var replay: Button
var next: Button
var elapsed := 0.0
var auto_play := true
var _backdrop
var _sound
var _steps: Array = []
var _engine_status: Label
var _autoplay_button: Button
var _sound_button: Button
var _serif: SystemFont

func _ready() -> void:
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["Georgia", "DejaVu Serif", "Liberation Serif"])
	_backdrop = Backdrop.new()
	add_child(_backdrop)
	_sound = Soundscape.new()
	add_child(_sound)
	add_child(_text("DUEL ARENA    /    MONSTER STUDIES", Vector2(80, 48), 14, ACCENT))
	add_child(_text("The Portrait's Secret", Vector2(76, 103), 55, INK, true))
	add_child(_text("A presence on the other side of the canvas.", Vector2(82, 181), 20, MUTED))
	_engine_status = _text("LIVE ENGINE    ·    TURN 01", Vector2(1490, 54), 13, Color("8da992"))
	add_child(_engine_status)
	add_child(_text("01  /  THE LIVING FRAME", Vector2(82, 287), 13, ACCENT))
	add_child(_text("EARTH", Vector2(82, 329), 19, INK))
	add_child(_text("Fiend  /  Normal Monster", Vector2(82, 367), 17, MUTED))
	add_child(_text("LEVEL  04", Vector2(82, 407), 14, Color("bfa78a")))
	add_child(_text("1200", Vector2(78, 477), 49, INK, true))
	add_child(_text("1500", Vector2(275, 477), 49, INK, true))
	add_child(_text("ATTACK", Vector2(82, 542), 12, MUTED))
	add_child(_text("DEFENSE", Vector2(280, 542), 12, MUTED))
	add_child(_text("Aged wood. Torn canvas.\nAn uneasy green light.\n\nThe portrait is not empty.", Vector2(82, 610), 18, Color("aaa0a5")))
	director = CardAnimationDirector.new()
	add_child(director)
	director.animation_started.connect(_sound.play_cue)
	for entry in [{"p": 0, "i": 0, "pos": Vector2(570, 220), "size": Vector2(700, 590)},
		{"p": 1, "i": 0, "pos": Vector2(1460, 280), "size": Vector2(220, 220)},
		{"p": 1, "i": 1, "pos": Vector2(1460, 575), "size": Vector2(220, 220)}]:
		var zone := Control.new()
		zone.position = entry["pos"]
		zone.size = entry["size"]
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(zone)
		director.register_zone(entry["p"], entry["i"], zone, false)
	add_child(_text("TRAINING TARGET", Vector2(1450, 546), 13, Color("a6a5a8")))
	add_child(_text("300 ATK", Vector2(1502, 572), 11, MUTED))
	add_child(_text("COUNTERATTACKER", Vector2(1450, 781), 13, Color("a6a5a8")))
	add_child(_text("2000 ATK", Vector2(1495, 807), 11, MUTED))
	move_child(director, get_child_count() - 1)
	caption = _text("", Vector2(82, 780), 24, INK, true)
	add_child(caption)
	detail = _text("", Vector2(82, 822), 14, MUTED)
	add_child(detail)
	for i in range(5):
		var panel := PanelContainer.new()
		panel.position = Vector2(80 + i * 356, 895)
		panel.size = Vector2(338, 49)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := _text("%02d    %s" % [i + 1, STEP_NAMES[i]], Vector2.ZERO, 13, MUTED)
		panel.add_child(label)
		add_child(panel)
		_steps.append(panel)
	replay = _button("Replay study", Vector2(80, 977), _restart)
	add_child(replay)
	next = _button("Next moment  →", Vector2(290, 977), _next)
	add_child(next)
	_autoplay_button = _toggle("Auto play", Vector2(570, 977), true, func(enabled): auto_play = enabled)
	add_child(_autoplay_button)
	var reduced := _toggle("Reduce motion", Vector2(780, 977), false, func(enabled):
		director.set_reduced_motion(enabled)
		_backdrop.reduced_motion = enabled)
	add_child(reduced)
	_sound_button = _toggle("Sound", Vector2(990, 977), true, _sound.set_enabled)
	add_child(_sound_button)
	add_child(_text("ORIGINAL PROCEDURAL STUDY\nPOLISH PASS  /  NOT FINAL CARD ART", Vector2(1500, 986), 11, Color("756b75")))
	_restart()

func _process(delta: float) -> void:
	elapsed += delta
	next.disabled = director.is_busy() or scenario.step >= 5
	_autoplay_button.set_pressed_no_signal(auto_play)
	if not director.active.is_empty():
		_backdrop.action = str(director.active["action"])
		var profile = director.registry.profile_for(director.active["card"])
		_backdrop.progress = director._elapsed / maxf(0.01, profile.duration(_backdrop.action))
	else:
		_backdrop.action = "idle"
		_backdrop.progress = 0.0
	if auto_play and elapsed > 3.6 and not director.is_busy() and scenario.step < 5: _next()

func _restart() -> void:
	director.skip()
	scenario = Scenario.new()
	director.ingest(0, [], scenario.snapshot())
	director.present(0)
	caption.text = "Before the awakening"
	detail.text = "Five moments. Every one begins in the rules engine."
	_engine_status.text = "LIVE ENGINE    ·    TURN 01"
	elapsed = 0
	_update_steps()

func _next() -> void:
	if director.is_busy() or scenario.step >= 5: return
	scenario.advance()
	var snapshot: Dictionary = scenario.snapshot()
	var events: Array = scenario.drain()
	director.ingest(0, events, snapshot)
	director.present(0)
	caption.text = str(STEP_NAMES[scenario.step - 1]).capitalize()
	detail.text = STEP_DESCRIPTIONS[scenario.step - 1]
	if not scenario.error.is_empty(): detail.text = scenario.error
	_engine_status.text = "LIVE ENGINE    ·    TURN %02d" % scenario.engine.state.turn_number
	elapsed = 0
	_update_steps()

func _update_steps() -> void:
	for i in range(_steps.size()):
		var active: bool = i == scenario.step - 1
		var complete: bool = i < scenario.step - 1
		var panel: PanelContainer = _steps[i]
		panel.add_theme_stylebox_override("panel", _box(Color("271f2a") if active else Color(0, 0, 0, 0), ACCENT if active else Color("3b303e"), 15))
		panel.get_child(0).add_theme_color_override("font_color", INK if active else (Color("a78b82") if complete else MUTED))

func _text(value: String, pos: Vector2, font_size: int, color: Color, serif: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if serif: label.add_theme_font_override("font", _serif)
	return label

func _button(value: String, pos: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.position = pos
	button.custom_minimum_size = Vector2(190, 51)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("665c68"))
	button.add_theme_stylebox_override("normal", _box(Color("201a24"), Color("59404b"), 14))
	button.add_theme_stylebox_override("hover", _box(Color("352330"), ACCENT, 14))
	button.add_theme_stylebox_override("pressed", _box(Color("462937"), ACCENT, 14))
	button.add_theme_stylebox_override("disabled", _box(Color("17141c"), Color("312932"), 14))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT, 14))
	button.pressed.connect(action)
	return button

func _toggle(value: String, pos: Vector2, initial: bool, action: Callable) -> Button:
	var button := _button(value, pos, func(): pass)
	button.toggle_mode = true
	button.button_pressed = initial
	button.toggled.connect(action)
	return button

static func _box(fill: Color, border: Color, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(margin)
	return box
