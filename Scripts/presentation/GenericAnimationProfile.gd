extends RefCounted

## Original abstract fallback, intentionally not an illustration of any licensed monster.
func duration(action: String) -> float:
	return {"summon": 0.75, "attack": 0.65, "position": 0.6, "destroy": 0.8}.get(action, 0.0)

func draw(canvas: CanvasItem, rect: Rect2, action: String, progress: float, time: float,
		defense: bool, target: Vector2) -> void:
	var p := clampf(progress, 0.0, 1.0)
	var center := rect.get_center()
	var tint := Color("7edbd0")
	var radius := minf(rect.size.x, rect.size.y) * 0.32
	var alpha := 1.0
	if action == "summon":
		radius *= smoothstep(0.0, 0.6, p)
		canvas.draw_arc(center, radius * (1.9 - p), 0, TAU, 40, Color(tint, 1.0 - p), 2, true)
	elif action == "attack":
		center += (target - center).limit_length(rect.size.y * 0.7) * sin(p * PI)
		if p > 0.25 and p < 0.8:
			canvas.draw_line(center, center.lerp(target, minf(1.0, (p - 0.25) * 3)), Color(tint, sin(p * PI)), 3, true)
	elif action == "destroy":
		alpha = 1.0 - p
		for i in range(12):
			var ray := Vector2.from_angle(i * TAU / 12.0)
			canvas.draw_circle(center + ray * radius * (1.0 + p * 3), 2.5 * alpha, Color("a4acb3", alpha))
	elif action == "position":
		radius *= maxf(0.08, absf(cos(p * PI)))
	var lean := 0.55 if defense else 1.0
	var points := PackedVector2Array([center + Vector2(0, -radius * lean), center + Vector2(radius, 0),
		center + Vector2(0, radius * lean), center + Vector2(-radius, 0), center + Vector2(0, -radius * lean)])
	canvas.draw_colored_polygon(points, Color("203b48", alpha))
	canvas.draw_polyline(points, Color(tint, alpha), 2, true)
	canvas.draw_circle(center, 3.0 + sin(time * 2.0) * 0.3, Color(tint, alpha))
