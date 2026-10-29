extends RefCounted

## Original procedural blocking pass, not finished card art or a ripped game asset.
## Coordinates are normalized around a wooden portrait, so the same choreography
## works in a board slot and a large inspection/demo viewport.
func duration(action: String) -> float:
	match action:
		"summon": return 1.65
		"attack": return 0.90
		"position": return 0.95
		"destroy": return 1.35
	return 0.0

func draw(canvas: CanvasItem, rect: Rect2, action: String, progress: float,
		time: float, defense: bool, target: Vector2) -> void:
	var p := clampf(progress, 0.0, 1.0)
	if action == "destroy" and p >= 1.0: return
	var center := rect.get_center()
	var dimensions := rect.size / 100.0
	var extension := 0.0 if defense else 1.0
	var back := defense
	var flip := 1.0
	var alpha := 1.0
	var split := 0.0
	var rise := 1.0
	if action == "summon":
		rise = smoothstep(0.0, 0.25, p)
		extension = smoothstep(0.30, 0.78, p) if not defense else 0.0
		center.y += rect.size.y * (1.0 - rise) * 0.22
	elif action == "position":
		# First retract, then rotate the frame onto its covered reverse side.
		# Going to attack runs the same choreography backwards.
		var phase := p if defense else 1.0 - p
		extension = 1.0 - smoothstep(0.0, 0.45, phase)
		var rotation_phase := smoothstep(0.35, 0.95, phase)
		flip = maxf(0.035, absf(cos(rotation_phase * PI)))
		back = rotation_phase > 0.5
	elif action == "attack":
		var lunge := sin(smoothstep(0.12, 0.78, p) * PI)
		center += (target - center) * lunge * 0.22
		dimensions *= 1.0 + lunge * 0.12
	elif action == "destroy":
		split = smoothstep(0.32, 0.82, p) * 29.0
		alpha = 1.0 - smoothstep(0.64, 1.0, p)
		extension *= 1.0 - smoothstep(0.08, 0.50, p)

	canvas.draw_set_transform(center, 0.0, dimensions * Vector2(flip, rise))
	var pulse := 0.72 + sin(time * 2.7) * 0.10
	if action == "summon": pulse *= 1.0 + sin(p * PI) * 0.65
	for i in range(5, 0, -1):
		var halo := Rect2(-33.0 - i * 2.6, -41.0 - i * 2.0, 66.0 + i * 5.2, 82.0 + i * 4.0)
		canvas.draw_rect(halo, Color(0.67, 0.06, 0.35, alpha * pulse * (0.025 + (5 - i) * 0.012)))
	var frame_color := Color(0.42, 0.20, 0.10, alpha)
	if split > 0.0:
		_half(canvas, true, split, alpha, back, frame_color)
		_half(canvas, false, split, alpha, back, frame_color)
	else:
		canvas.draw_rect(Rect2(-30, -39, 60, 78), Color(0.055, 0.025, 0.065, alpha))
		if back:
			_back(canvas, alpha)
		else:
			canvas.draw_rect(Rect2(-26, -35, 52, 70), Color(0.17, 0.13, 0.16, alpha))
			# Blank woven canvas remains visible before the creature breaks through.
			for y in range(-32, 35, 5):
				canvas.draw_line(Vector2(-25, y), Vector2(25, y), Color(0.37, 0.29, 0.29, alpha * 0.22), 0.6)
		_frame(canvas, frame_color, alpha)
		if not back and extension > 0.0:
			_creature(canvas, extension, time, alpha, action == "attack")
	if action == "destroy":
		var crack_alpha := smoothstep(0.0, 0.22, p) * alpha
		canvas.draw_polyline(PackedVector2Array([Vector2(-8,-42), Vector2(-3,-31), Vector2(-10,-20), Vector2(1,-9), Vector2(-4,3), Vector2(6,14), Vector2(-1,28), Vector2(5,43)]), Color(0.035,0.025,0.035,crack_alpha), 2.2, true)
		for i in range(24):
			var birth := float(i % 6) * 0.035 + 0.40
			var age := maxf(0.0, p - birth)
			if age <= 0.0: continue
			var direction := Vector2(sin(i * 2.399), cos(i * 1.771))
			var point := Vector2(sin(i * 3.1) * 22, cos(i * 2.7) * 30) + direction * age * 65 + Vector2(0, age * age * 74)
			canvas.draw_circle(point, 1.5 + float(i % 3) * 0.6 + age * 3, Color(0.54, 0.53, 0.56, (1.0 - smoothstep(0.55, 1.0, p)) * 0.65))
	canvas.draw_set_transform(Vector2.ZERO)
	if action == "attack": _slash(canvas, target, rect.size, p)

func _frame(canvas: CanvasItem, wood: Color, alpha: float) -> void:
	canvas.draw_rect(Rect2(-34, -43, 68, 8), wood)
	canvas.draw_rect(Rect2(-34, 35, 68, 8), wood)
	canvas.draw_rect(Rect2(-34, -43, 8, 86), wood)
	canvas.draw_rect(Rect2(26, -43, 8, 86), wood)
	canvas.draw_rect(Rect2(-31, -40, 62, 80), Color(0.77, 0.48, 0.23, alpha), false, 1.4)
	canvas.draw_rect(Rect2(-27, -36, 54, 72), Color(0.19, 0.08, 0.05, alpha), false, 1.2)
	for y in [-40.0, 38.0]:
		canvas.draw_line(Vector2(-29,y), Vector2(29,y + 1), Color(0.25,0.11,0.06,alpha), 0.7)
	for x in [-30.0, 30.0]:
		canvas.draw_line(Vector2(x,-30), Vector2(x + 1,29), Color(0.24,0.10,0.06,alpha), 0.8)
	for corner in [Vector2(-30,-39), Vector2(30,-39), Vector2(-30,39), Vector2(30,39)]:
		canvas.draw_circle(corner, 1.1, Color(0.82,0.63,0.33,alpha))

func _back(canvas: CanvasItem, alpha: float) -> void:
	canvas.draw_rect(Rect2(-26,-35,52,70), Color(0.24,0.15,0.13,alpha))
	for x in range(-22,26,9):
		canvas.draw_line(Vector2(x,-34),Vector2(x,34),Color(0.13,0.08,0.075,alpha),1.0)
	canvas.draw_line(Vector2(-23,-28),Vector2(23,28),Color(0.42,0.31,0.23,alpha),5.0)
	canvas.draw_line(Vector2(23,-28),Vector2(-23,28),Color(0.42,0.31,0.23,alpha),5.0)
	canvas.draw_circle(Vector2(0,-28),2.0,Color(0.70,0.58,0.39,alpha))

func _creature(canvas: CanvasItem, extension: float, time: float, alpha: float, attacking: bool) -> void:
	var e := extension
	var breath := sin(time * 2.1) * 0.7 * e
	# Torn opening is jagged rather than a uniform ellipse.
	var hole := PackedVector2Array()
	for i in range(20):
		var angle := float(i) * TAU / 20.0
		var radius := (1.0 if i % 2 == 0 else 0.80) * e
		hole.append(Vector2(cos(angle) * 23.0 * radius, sin(angle) * 28.0 * radius + 2))
	canvas.draw_colored_polygon(hole,Color(0.035,0.015,0.055,alpha))
	canvas.draw_polyline(hole,Color(0.54,0.34,0.39,alpha * e),1.2,true)
	# Angular head and two luminous eyes emerge only after the claw's first breach.
	var head := smoothstep(0.38,0.95,e)
	var offset := (1.0 - head) * 12.0 + breath
	var head_poly := PackedVector2Array([Vector2(-14,-18 + offset),Vector2(-9,-27 + offset),Vector2(9,-26 + offset),Vector2(16,-13 + offset),Vector2(9,3 + offset),Vector2(-8,4 + offset)])
	canvas.draw_colored_polygon(head_poly,Color(0.13,0.32,0.20,alpha * head))
	for x in [-6.0,7.0]:
		for glow in range(3,0,-1):
			canvas.draw_circle(Vector2(x,-12 + offset),float(glow) * 2,Color(0.61,1.0,0.31,alpha * head * 0.10))
		canvas.draw_line(Vector2(x-3,-13 + offset),Vector2(x+2,-12 + offset),Color(0.81,1.0,0.43,alpha * head),2.0,true)
	var hand_y := 26.0 - e * 13.0 + breath
	var skin := Color(0.26,0.58,0.26,alpha * e)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(3,34),Vector2(-5,hand_y+11),Vector2(-15,hand_y+3),Vector2(-12,hand_y-6),Vector2(3,hand_y-9),Vector2(15,hand_y+1),Vector2(12,hand_y+10)]),skin)
	for i in range(4):
		var x := -12.0 + i * 7.0
		var length := (18.0 if attacking else 12.0) * e + sin(time * 1.8 + i) * e
		var tip := Vector2(x - 4.0,hand_y - length)
		canvas.draw_line(Vector2(x,hand_y+1),Vector2(x-2,hand_y-length*0.65),skin,5.0,true)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(x-4,hand_y-length*0.55),Vector2(x+1,hand_y-length*0.55),tip]),Color(0.78,0.93,0.59,alpha*e))

func _half(canvas: CanvasItem, left: bool, split: float, alpha: float, back: bool, wood: Color) -> void:
	var sign_x := -1.0 if left else 1.0
	var shift := sign_x * split
	var polygon := PackedVector2Array([Vector2(shift, -35),Vector2(shift + sign_x * 26,-35),Vector2(shift + sign_x * 26,35),Vector2(shift,35),Vector2(shift + sign_x * 5,24),Vector2(shift - sign_x * 3,11),Vector2(shift + sign_x * 4,-3),Vector2(shift - sign_x * 2,-16)])
	canvas.draw_colored_polygon(polygon,Color(0.24,0.15,0.13,alpha) if back else Color(0.17,0.13,0.16,alpha))
	var outer := shift + sign_x * 30
	canvas.draw_rect(Rect2(outer-4,-43,8,86),wood)
	var x := shift - 4 if left else shift
	if left: x = shift - 34
	canvas.draw_rect(Rect2(x,-43,34,8),wood)
	canvas.draw_rect(Rect2(x,35,34,8),wood)
	canvas.draw_line(Vector2(outer,-39),Vector2(outer,39),Color(0.77,0.48,0.23,alpha),1.4)

func _slash(canvas: CanvasItem, target: Vector2, dimensions: Vector2, p: float) -> void:
	var visibility := smoothstep(0.28,0.40,p) * (1.0-smoothstep(0.58,0.86,p))
	if visibility <= 0.0: return
	var extent := maxf(dimensions.x,dimensions.y) * 0.55
	for i in range(3):
		var offset := Vector2((i-1)*extent*0.22,0)
		var start := target+offset+Vector2(extent*0.26,-extent*0.45)
		var end := target+offset+Vector2(-extent*0.26,extent*0.45)
		var points := PackedVector2Array([start,start.lerp(end,0.5)+Vector2(-extent*0.07,0),end])
		canvas.draw_polyline(points,Color(0.60,0.16,0.84,visibility*0.28),maxf(5.0,extent*0.13),true)
		canvas.draw_polyline(points,Color(0.57,0.97,0.33,visibility),maxf(2.0,extent*0.045),true)
		canvas.draw_polyline(points,Color(0.91,1.0,0.79,visibility),maxf(1.0,extent*0.013),true)
