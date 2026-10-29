extends Control

## F6 / explicit scene only. Arranged engine fixture, not a playable campaign or CPU.
const Scenario = preload("res://Scripts/presentation/demo/PortraitAnimationScenario.gd")
var scenario
var director: CardAnimationDirector
var caption: Label
var detail: Label
var replay: Button
var next: Button
var elapsed := 0.0
var auto_play := true

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1420")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := _text("THE PORTRAIT'S SECRET", Vector2(100, 65), 40, Color("f0d6e5"))
	add_child(title)
	add_child(_text("ORIGINAL PROCEDURAL ANIMATION STUDY   /   REAL ENGINE EVENTS", Vector2(104, 120), 16, Color("bd7a9e")))
	add_child(_text("EARTH · FIEND · NORMAL · LEVEL 4 · ATK 1200 / DEF 1500", Vector2(104, 153), 16, Color("b5c8d0")))
	add_child(_text("A blocking prototype, not finished high-fidelity card art. Production decks unchanged.", Vector2(104, 195), 17, Color("8096a5")))
	director = CardAnimationDirector.new()
	add_child(director)
	for entry in [{"p": 0, "i": 0, "pos": Vector2(270, 300), "label": "THE PORTRAIT'S SECRET"},
		{"p": 1, "i": 0, "pos": Vector2(1040, 280), "label": "TRAINING TARGET"},
		{"p": 1, "i": 1, "pos": Vector2(1390, 280), "label": "COUNTERATTACKER"}]:
		var zone := Control.new()
		zone.position = entry["pos"]
		zone.size = Vector2(320, 360) if entry["p"] == 0 else Vector2(220, 270)
		add_child(zone)
		director.register_zone(entry["p"], entry["i"], zone, false)
		add_child(_text(entry["label"], zone.position + Vector2(-5, zone.size.y + 35), 17, Color("c0d0d7")))
	# Keep drawing above fixture anchors; controls do not intercept the effects.
	move_child(director, get_child_count() - 1)
	caption = _text("", Vector2(104, 805), 25, Color("f4d6e3"))
	add_child(caption)
	detail = _text("", Vector2(104, 850), 16, Color("91a6b7"))
	add_child(detail)
	replay = _button("Replay fixture", Vector2(104, 930), _restart)
	add_child(replay)
	next = _button("Next engine action", Vector2(320, 930), _next)
	add_child(next)
	var autoplay := CheckButton.new()
	autoplay.position = Vector2(600, 930)
	autoplay.text = "Auto play"
	autoplay.button_pressed = true
	autoplay.toggled.connect(func(enabled): auto_play = enabled)
	add_child(autoplay)
	var reduced := CheckButton.new()
	reduced.position = Vector2(800, 930)
	reduced.text = "Reduce motion"
	reduced.toggled.connect(director.set_reduced_motion)
	add_child(reduced)
	_restart()

func _process(delta: float) -> void:
	elapsed += delta
	next.disabled = director.is_busy() or scenario.step >= 5
	if auto_play and elapsed > 2.7 and not director.is_busy() and scenario.step < 5: _next()

func _restart() -> void:
	director.skip()
	scenario = Scenario.new()
	director.ingest(0, [], scenario.snapshot())
	director.present(0)
	caption.text = "READY · a legally offered Normal Summon starts the sequence"
	detail.text = "Five engine actions. Turns advance legally between manual position changes."
	elapsed = 0

func _next() -> void:
	if director.is_busy() or scenario.step >= 5: return
	caption.text = scenario.advance()
	var snapshot: Dictionary = scenario.snapshot()
	var events: Array = scenario.drain()
	director.ingest(0, events, snapshot)
	director.present(0)
	detail.text = "Step %d / 5 · Turn %d · projected events: %d · no rules changed by animation" % [scenario.step, scenario.engine.state.turn_number, events.size()]
	elapsed = 0

static func _text(value: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

static func _button(value: String, pos: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.position = pos
	button.custom_minimum_size = Vector2(200, 55)
	button.pressed.connect(action)
	return button
