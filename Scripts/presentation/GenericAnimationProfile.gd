extends RefCounted

## Original faceted hologram fallback. Abstract by design, never a fabricated monster portrait.
func duration(action: String) -> float:
	return {"summon": 0.85, "attack": 0.72, "position": 0.65, "destroy": 0.9}.get(action, 0.0)

func draw(canvas: CanvasItem, rect: Rect2, action: String, progress: float, time: float,
		defense: bool, target: Vector2) -> void:
	var p := clampf(progress, 0.0, 1.0)
	var center := rect.get_center() + Vector2(0, sin(time * 1.6) * rect.size.y * 0.025)
	var radius := minf(rect.size.x, rect.size.y) * 0.30
	var tint := Color("8fe4d6")
	var alpha := 1.0
	var emerge := 1.0
	if action == "summon":
		emerge = smoothstep(0.0, 0.65, p)
		center.y += (1.0 - emerge) * rect.size.y * 0.18
		for i in range(3):
			var rip := fmod(p + i * 0.2, 1.0)
			_ring(canvas, center + Vector2(0, radius * 0.65), Vector2(radius * (0.9 + rip), radius * 0.27), Color(tint, (1.0 - rip) * (1.0 - p) * 0.5), 1.2)
	elif action == "attack":
		var lunge := smoothstep(0.1, 0.38, p) * (1.0 - smoothstep(0.5, 0.95, p))
		center += (target - center).limit_length(rect.size.y * 0.85) * lunge
		var beam := smoothstep(0.22, 0.4, p) * (1.0 - smoothstep(0.65, 0.88, p))
		if beam > 0.001:
			var axis := (target - center).normalized()
			var normal := Vector2(-axis.y, axis.x)
			var tip := center.lerp(target, smoothstep(0.22, 0.52, p))
			canvas.draw_colored_polygon(PackedVector2Array([center - normal * radius * 0.23, tip, center + normal * radius * 0.23]), Color(tint, beam * 0.24))
			canvas.draw_line(center, tip, Color("d4fff2", beam), 1.6, true)
	elif action == "destroy":
		alpha = 1.0 - smoothstep(0.15, 1.0, p)
		for i in range(10):
			var ray := Vector2.from_angle(i * TAU / 10.0 + 0.25)
			var point := center + ray * radius * (0.5 + p * 2.0) + Vector2(0, p * p * radius)
			var side := Vector2(-ray.y, ray.x)
			canvas.draw_colored_polygon(PackedVector2Array([point - ray * 4, point + side * 1.8, point + ray * 6, point - side * 1.8]), Color(tint, alpha * 0.6))
	elif action == "position":
		emerge = maxf(0.06, absf(cos(p * PI)))
	if alpha <= 0.001 or emerge <= 0.001: return
	_ring(canvas, center + Vector2(0, radius * 0.8), Vector2(radius * 1.23, radius * 0.27), Color(tint, alpha * 0.20), 1)
	for i in range(5, 0, -1):
		canvas.draw_circle(center, radius * (0.7 + i * 0.12), Color(tint, alpha * 0.012), true, -1, true)
	var lean := 0.60 if defense else 1.15
	var top := center + Vector2(0, -radius * lean)
	var right := center + Vector2(radius * emerge, 0)
	var bottom := center + Vector2(0, radius * lean)
	var left := center + Vector2(-radius * emerge, 0)
	var inner := center + Vector2(-radius * 0.15, -radius * 0.10)
	canvas.draw_colored_polygon(PackedVector2Array([top, right, inner]), Color("3b7979", alpha))
	canvas.draw_colored_polygon(PackedVector2Array([right, bottom, inner]), Color("173c4a", alpha))
	canvas.draw_colored_polygon(PackedVector2Array([bottom, left, inner]), Color("285d67", alpha))
	canvas.draw_colored_polygon(PackedVector2Array([left, top, inner]), Color("66a69c", alpha))
	canvas.draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(tint, alpha * 0.82), 1.5, true)
	for point in [top, right, bottom, left]: canvas.draw_line(point, inner, Color(tint, alpha * 0.30), 0.9, true)
	canvas.draw_circle(inner, maxf(1.1, radius * 0.045), Color("dafff0", alpha), true, -1, true)

func _ring(canvas: CanvasItem, center: Vector2, radius: Vector2, tint: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(49):
		var angle := float(i) * TAU / 48.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_polyline(points, tint, width, true)
