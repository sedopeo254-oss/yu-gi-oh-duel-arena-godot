extends Control

## Original presentation set: charcoal gallery, soft stage light and floating dust.
const Atmosphere = preload("res://Assets/shaders/portrait_atmosphere.gdshader")
var reduced_motion := false
var action := "idle"
var progress := 0.0
var _time := 0.0
var _fog: ColorRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog = ColorRect.new()
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material_instance := ShaderMaterial.new()
	material_instance.shader = Atmosphere
	_fog.material = material_instance
	add_child(_fog)
	move_child(_fog, 0)
	_fog.show_behind_parent = true

func _process(delta: float) -> void:
	if not reduced_motion: _time += delta
	var energy := sin(progress * PI) if action in ["summon", "destroy"] else 0.0
	if action == "attack": energy = maxf(0, 1.0 - absf(progress - 0.48) * 7.0) * 0.8
	_fog.material.set_shader_parameter("scene_time", 0.0 if reduced_motion else _time)
	_fog.material.set_shader_parameter("energy", 0.0 if reduced_motion else energy)
	_fog.material.set_shader_parameter("glow_tint", Color("788b69") if action == "destroy" else Color("882b68"))
	queue_redraw()

func _draw() -> void:
	var sx := size.x / 1920.0
	var sy := size.y / 1080.0
	draw_set_transform(Vector2.ZERO, 0, Vector2(sx, sy))
	# Panel hairlines and a shallow gallery floor supply depth without decorative clutter.
	for x in [520.0, 1325.0]:
		draw_line(Vector2(x, 240), Vector2(x, 820), Color(0.49, 0.38, 0.45, 0.12), 1, true)
	for i in range(14, 0, -1):
		var a := 0.010 * (1.0 - float(i) / 18.0)
		_oval(Vector2(920, 832), Vector2(340 + i * 7, 18 + i * 2.4), Color(0.57, 0.13, 0.35, a))
	_oval(Vector2(920, 832), Vector2(265, 16), Color(0.015, 0.012, 0.022, 0.55))
	for i in range(46):
		var phase := float(i) * 2.399963
		var x := 570 + fmod(float(i) * 83.71 + sin(_time * 0.16 + phase) * 22.0, 680.0)
		var y := 260 + fmod(float(i) * 53.19 - _time * (3.0 + float(i % 5)) + 9000.0, 560.0)
		var opacity := (0.16 + sin(_time * 0.8 + phase) * 0.09) * sin((y - 260) / 560.0 * PI)
		draw_circle(Vector2(x, y), 0.65 + float(i % 3) * 0.35, Color(0.83, 0.63, 0.66, opacity), true, -1, true)
	draw_line(Vector2(80, 876), Vector2(1840, 876), Color("4a343d", 0.55), 1, true)
	draw_set_transform(Vector2.ZERO)

func _oval(center: Vector2, radius: Vector2, tint: Color) -> void:
	var points := PackedVector2Array()
	for i in range(64):
		var angle := float(i) * TAU / 64.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, tint)
