extends RefCounted

## Original procedural 2.5D portrait. No external artwork or game assets.
## All details share normalized coordinates; the director owns event timing and visibility.
func duration(action: String) -> float:
	match action:
		"summon": return 2.10
		"attack": return 1.15
		"position": return 1.20
		"destroy": return 1.75
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
	var tilt := sin(time * 0.85) * 0.008
	if action == "summon":
		rise = smoothstep(0.0, 0.24, p)
		extension = smoothstep(0.27, 0.85, p) if not defense else 0.0
		center.y += rect.size.y * (1.0 - rise) * 0.17
		tilt += sin(p * PI) * -0.045
	elif action == "position":
		var phase := p if defense else 1.0 - p
		extension = 1.0 - smoothstep(0.0, 0.47, phase)
		var rotation_phase := smoothstep(0.36, 0.96, phase)
		flip = maxf(0.035, absf(cos(rotation_phase * PI)))
		back = rotation_phase > 0.5
	elif action == "attack":
		var recoil := smoothstep(0.0, 0.18, p) * (1.0 - smoothstep(0.18, 0.32, p))
		var lunge := smoothstep(0.20, 0.39, p) * (1.0 - smoothstep(0.52, 0.94, p))
		center += (target - center) * (lunge * 0.23 - recoil * 0.035)
		dimensions *= 1.0 + lunge * 0.15 - recoil * 0.035
		tilt += recoil * -0.055 + lunge * 0.045
	elif action == "destroy":
		split = smoothstep(0.30, 0.87, p) * 28.0
		alpha = 1.0 - smoothstep(0.64, 1.0, p)
		extension *= 1.0 - smoothstep(0.12, 0.49, p)
		tilt = sin(p * 71.0) * 0.025 * (1.0 - p)
	canvas.draw_set_transform(center, tilt, dimensions * Vector2(flip, maxf(0.01, rise)))
	_atmosphere(canvas, time, alpha * rise, action == "summon", p)
	if split > 0.0:
		_torn_half(canvas, -1.0, split, alpha, time)
		_torn_half(canvas, 1.0, split, alpha, time)
	else:
		_canvas(canvas, alpha, back)
		if not back and extension > 0.0: _void(canvas, extension, alpha, time)
		_frame(canvas, alpha)
		if not back and extension > 0.0: _creature(canvas, extension, time, alpha, action == "attack", p)
	if action == "destroy": _destruction(canvas, p, alpha)
	canvas.draw_set_transform(Vector2.ZERO)
	if action == "attack": _slash(canvas, target, rect.size, p)

func _ellipse(c: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		var angle := float(i) * TAU / 40.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	c.draw_colored_polygon(points, color)

func _poly(c: CanvasItem, points: Array, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array(points), color)

func _curve(c: CanvasItem, a: Vector2, b: Vector2, d: Vector2, e: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(17): points.append(a.bezier_interpolate(b, d, e, float(i) / 16.0))
	c.draw_polyline(points, color, width, true)

func _atmosphere(c: CanvasItem, time: float, alpha: float, summon: bool, p: float) -> void:
	# Offset soft shadow and a layered, non-rectangular magenta volume.
	for i in range(10, 0, -1):
		_ellipse(c, Vector2(4, 5), Vector2(31 + i * 0.9, 39 + i), Color(0.005, 0.004, 0.014, alpha * 0.05))
	var energy := 1.0 + (sin(p * PI) * 0.8 if summon else 0.0)
	for i in range(12, 0, -1):
		var breath := sin(time * 1.5 + i * 0.2)
		_ellipse(c, Vector2(breath * 1.2, -1), Vector2(31 + i * 1.5, 38 + i * 1.2), Color(0.52, 0.025, 0.23, alpha * energy * 0.017))
	for side in [-1.0, 1.0]:
		for i in range(3):
			var x: float = side * (34.0 + i * 2.3)
			var drift := sin(time * 1.4 + i * 1.7) * 3
			_curve(c, Vector2(x, 37), Vector2(x + side * 12, 12 + drift), Vector2(x - side * 9, -18), Vector2(x + side * 3, -43), Color(0.76, 0.12, 0.44, alpha * 0.12), 1.1 + i * 0.4)

func _canvas(c: CanvasItem, alpha: float, back: bool) -> void:
	c.draw_rect(Rect2(-28, -36, 56, 72), Color(0.11, 0.075, 0.09, alpha))
	for i in range(12, 0, -1):
		_ellipse(c, Vector2(-4, -3), Vector2(26, 35) * (float(i) / 12.0), Color(0.34, 0.27, 0.23, alpha * 0.035))
	# Fine woven fibers, deliberately quiet so the tear reads as a silhouette.
	for i in range(39):
		var y := -34.0 + i * 1.8
		c.draw_line(Vector2(-26,y), Vector2(26,y + sin(i * 2.7) * 0.35), Color(0.62,0.49,0.35,alpha * (0.08 + sin(i * 1.7) * 0.035)),0.22)
	for i in range(29):
		var x := -25.0 + i * 1.8
		c.draw_line(Vector2(x,-34),Vector2(x + 0.2,34),Color(0.045,0.028,0.035,alpha * 0.18),0.27)
	if back:
		for i in range(7):
			var x := -25.0 + i * 8
			c.draw_line(Vector2(x,-34),Vector2(x,34),Color(0.07,0.04,0.035,alpha),0.6)
		for side in [-1.0,1.0]:
			c.draw_line(Vector2(-23,side * 29),Vector2(23,-side * 29),Color(0.12,0.07,0.04,alpha),5.8,true)
			c.draw_line(Vector2(-23,side * 29-0.6),Vector2(23,-side * 29-0.6),Color(0.38,0.25,0.13,alpha),3.3,true)
		c.draw_arc(Vector2(0,-28),2.1,0,TAU,24,Color(0.67,0.48,0.25,alpha),0.8,true)

func _frame(c: CanvasItem, alpha: float) -> void:
	# Four mitred boards, with alternating bevels (light from the upper left).
	var boards := [
		[Vector2(-35,-44),Vector2(35,-44),Vector2(26,-35),Vector2(-26,-35)],
		[Vector2(35,-44),Vector2(35,44),Vector2(26,35),Vector2(26,-35)],
		[Vector2(35,44),Vector2(-35,44),Vector2(-26,35),Vector2(26,35)],
		[Vector2(-35,44),Vector2(-35,-44),Vector2(-26,-35),Vector2(-26,35)]]
	var colors := [Color(0.38,0.19,0.085,alpha),Color(0.24,0.095,0.038,alpha),Color(0.29,0.12,0.045,alpha),Color(0.43,0.23,0.10,alpha)]
	for i in range(4): _poly(c,boards[i],colors[i])
	for i in range(7):
		var inset := float(i) * 0.72
		var light: float = [0.35,0.62,0.31,0.20,0.50,0.25,0.16][i]
		c.draw_rect(Rect2(-34 + inset,-43 + inset,68-inset*2,86-inset*2),Color(light,light*0.58,light*0.28,alpha),false,0.65)
	# Irregular grain and fine scratches run with each board, not across the joints.
	for side in [-1.0,1.0]:
		for i in range(9):
			var x: float = side * (28.0 + i * 0.61)
			_curve(c,Vector2(x,-31),Vector2(x+sin(i)*0.7,-12),Vector2(x-side*0.5,15),Vector2(x,31),Color(0.10,0.045,0.022,alpha*0.48),0.24)
		for i in range(8):
			var y: float = side * (37.0 + i * 0.64)
			_curve(c,Vector2(-24,y),Vector2(-7,y-0.4),Vector2(11,y+sin(i)*0.5),Vector2(24,y),Color(0.12,0.055,0.022,alpha*0.55),0.24)
		# Carved acanthus-like curls, original simple ornament.
		for y in [-23.0,0.0,23.0]:
			for facing in [-1.0,1.0]:
				_curve(c,Vector2(side*30,y),Vector2(side*25,y+facing*2),Vector2(side*34,y+facing*7),Vector2(side*30,y+facing*8),Color(0.69,0.39,0.15,alpha*0.62),0.55)
	c.draw_rect(Rect2(-27.2,-36.2,54.4,72.4),Color(0.78,0.56,0.25,alpha),false,0.8)
	c.draw_rect(Rect2(-26.4,-35.4,52.8,70.8),Color(0.10,0.055,0.035,alpha),false,0.7)
	for corner in [Vector2(-30.5,-39.5),Vector2(30.5,-39.5),Vector2(-30.5,39.5),Vector2(30.5,39.5)]:
		_ellipse(c,corner,Vector2(3.0,3.0),Color(0.16,0.10,0.05,alpha))
		for j in range(8):
			var direction := Vector2.from_angle(j*TAU/8)
			_ellipse(c,corner+direction*1.5,Vector2(0.85,0.85),Color(0.59,0.39,0.16,alpha))
		_ellipse(c,corner-Vector2(0.3,0.3),Vector2(1.1,1.1),Color(0.87,0.67,0.34,alpha))
		_ellipse(c,corner,Vector2(0.38,0.38),Color(0.18,0.12,0.055,alpha))

func _void(c: CanvasItem, extension: float, alpha: float, time: float) -> void:
	var e := extension
	var edge := PackedVector2Array()
	for i in range(38):
		var angle := float(i)*TAU/38
		var uneven := 0.91 + sin(i * 7.7)*0.065 + sin(i*2.3)*0.04
		edge.append(Vector2(cos(angle)*24.0,sin(angle)*32.0)*e*uneven + Vector2(0,1))
	c.draw_colored_polygon(edge,Color(0.018,0.011,0.030,alpha))
	for i in range(edge.size()):
		var a := edge[i]
		var b := edge[(i+1)%edge.size()]
		var outward := (a-Vector2(0,1)).normalized()
		var fold := a.lerp(b,0.48) + outward*(0.6+fmod(float(i)*1.7,2.3))*e
		_poly(c,[a,b,fold],Color(0.42+sin(i)*0.09,0.31,0.23,alpha))
		c.draw_line(a,fold,Color(0.79,0.64,0.44,alpha*0.58),0.38,true)
		if i%2==0:
			c.draw_line(fold,fold+outward*1.5*e+Vector2(sin(time+i),0)*0.25,Color(0.70,0.57,0.39,alpha*0.45),0.22,true)
	for i in range(7,0,-1):
		_ellipse(c,Vector2(0,-8),Vector2(17+i,22+i)*e,Color(0.11,0.035,0.13,alpha*0.022))

func _creature(c: CanvasItem, extension: float, time: float, alpha: float, attacking: bool, p: float) -> void:
	var e := extension
	var head := smoothstep(0.35,0.94,e)
	var breath := sin(time*1.6)*0.55*e
	var offset := Vector2(0,(1.0-head)*10 + breath)
	var ha := alpha * head
	# Neck, shoulders and gaunt head have curved silhouettes rather than a flat polygon.
	_ellipse(c,Vector2(0,7)+offset,Vector2(17,12),Color(0.035,0.10,0.065,ha))
	_ellipse(c,Vector2(0,-10)+offset,Vector2(13.5,20),Color(0.06,0.16,0.105,ha))
	for i in range(15,0,-1):
		var f := float(i)/15.0
		_ellipse(c,Vector2(-2.8,-14)+offset,Vector2(10.5,16)*f,Color(0.25,0.43,0.25,ha*0.065))
	# Temple and cheek planes recede into the void. A broken rim light separates them.
	_curve(c,Vector2(-12,-22)+offset,Vector2(-16,-9)+offset,Vector2(-10,4)+offset,Vector2(-4,8)+offset,Color(0.35,0.57,0.33,ha*0.50),0.7)
	_curve(c,Vector2(10,-25)+offset,Vector2(15,-11)+offset,Vector2(10,5)+offset,Vector2(4,8)+offset,Color(0.19,0.38,0.24,ha*0.5),0.5)
	_ellipse(c,Vector2(-8,0)+offset,Vector2(4.5,7),Color(0.035,0.085,0.065,ha*0.75))
	_ellipse(c,Vector2(8,0)+offset,Vector2(4.5,7),Color(0.025,0.06,0.055,ha*0.85))
	for side in [-1.0,1.0]:
		var eye := Vector2(side*6.2,-12.2)+offset
		_ellipse(c,eye+Vector2(0,0.5),Vector2(5.4,4.5),Color(0.012,0.025,0.022,ha))
		for glow in range(5,0,-1): _ellipse(c,eye,Vector2(3.2+glow,1.4+glow*0.6),Color(0.52,0.95,0.24,ha*0.028))
		var inner := eye+Vector2(-side*3.0,-0.1)
		var outer := eye+Vector2(side*3.8,-1.5)
		_poly(c,[inner,eye+Vector2(side*0.4,-1.6),outer,eye+Vector2(side*1.3,1.2)],Color(0.63,0.93,0.29,ha))
		_ellipse(c,eye+Vector2(side*0.5,-0.2),Vector2(0.55,1.3),Color(0.018,0.11,0.025,ha))
		_ellipse(c,eye+Vector2(-0.6,-0.7),Vector2(0.44,0.44),Color(0.95,1.0,0.74,ha))
		_curve(c,eye+Vector2(-side*3.5,-2),eye+Vector2(-side*1.0,-5),eye+Vector2(side*4,-5),eye+Vector2(side*5.2,-2),Color(0.30,0.47,0.26,ha),1.5)
		_curve(c,eye+Vector2(-side*3,-2.2),eye+Vector2(0,-3.8),eye+Vector2(side*3,-4),eye+Vector2(side*4,-2.9),Color(0.51,0.66,0.36,ha*0.6),0.38)
	# Nose bridge, hooked tip, nostrils, restrained mouth and chin.
	_curve(c,Vector2(-1.4,-13)+offset,Vector2(-3,-6)+offset,Vector2(-4,-3)+offset,Vector2(0,-2)+offset,Color(0.42,0.57,0.32,ha),1.4)
	_curve(c,Vector2(1,-12)+offset,Vector2(1,-6)+offset,Vector2(5,-2)+offset,Vector2(0,-2)+offset,Color(0.035,0.10,0.065,ha),2.3)
	for x in [-2.1,2.1]: _ellipse(c,Vector2(x,-1.8)+offset,Vector2(1.0,0.6),Color(0.015,0.04,0.025,ha))
	_curve(c,Vector2(-5,3)+offset,Vector2(-2,1)+offset,Vector2(2,4)+offset,Vector2(5,1.7)+offset,Color(0.02,0.04,0.028,ha),1.2)
	_curve(c,Vector2(-3,5.2)+offset,Vector2(-1,6)+offset,Vector2(2,6)+offset,Vector2(3,4.8)+offset,Color(0.32,0.43,0.25,ha*0.7),0.6)
	for i in range(3):
		_curve(c,Vector2(-8,-24+i*1.7)+offset,Vector2(-3,-26+i*1.7)+offset,Vector2(2,-25+i*1.7)+offset,Vector2(6,-24+i*1.7)+offset,Color(0.10,0.23,0.14,ha*0.8),0.45)
	_hand(c,e,time,alpha,attacking,p,breath)

func _limb(c: CanvasItem, a: Vector2, b: Vector2, d: Vector2, end: Vector2, radius: float, alpha: float) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var ridge := PackedVector2Array()
	for i in range(20):
		var t := float(i)/19.0
		var point := a.bezier_interpolate(b,d,end,t)
		var tangent := a.bezier_derivative(b,d,end,t).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var width := radius * (1.0-t*0.61) * (1.0+sin(t*PI*2)*0.07)
		left.append(point+normal*width)
		right.append(point-normal*width)
		ridge.append(point+normal*width*0.34)
	# Tight hooked Béziers can make an expanded outline self-intersect. Draw the
	# ribbon as independent triangles instead of asking polygon triangulation to
	# resolve that outline. Overlap is harmless; degenerates are explicitly skipped.
	for i in range(left.size() - 1):
		_triangle(c, left[i], right[i], left[i + 1], Color(0.20,0.40,0.20,alpha))
		_triangle(c, right[i], right[i + 1], left[i + 1], Color(0.20,0.40,0.20,alpha))
	c.draw_polyline(left,Color(0.53,0.69,0.34,alpha*0.8),0.65,true)
	c.draw_polyline(right,Color(0.035,0.13,0.07,alpha),0.85,true)
	c.draw_polyline(ridge,Color(0.35,0.56,0.27,alpha*0.7),radius*0.58,true)
	for t in [0.35,0.65]:
		var point := a.bezier_interpolate(b,d,end,t)
		var tangent := a.bezier_derivative(b,d,end,t).normalized()
		var normal: Vector2 = Vector2(-tangent.y,tangent.x)*radius*(1.0-t*0.6)*0.7
		c.draw_line(point-normal,point+normal,Color(0.08,0.23,0.12,alpha*0.8),0.42,true)

func _triangle(c: CanvasItem, a: Vector2, b: Vector2, d: Vector2, color: Color) -> void:
	if absf((b - a).cross(d - a)) < 0.00001: return
	c.draw_colored_polygon(PackedVector2Array([a, b, d]), color)

func _hand(c: CanvasItem, extension: float, time: float, alpha: float, attacking: bool, p: float, breath: float) -> void:
	var e := smoothstep(0.05,0.76,extension)
	var ha := alpha*e
	var origin := Vector2(2,32-(e*13)+breath)
	var reach := (sin(p*PI)*3.0 if attacking else 0.0)
	# Narrow wrist emerging below a raised palm, with visibly separate finger roots.
	_limb(c,Vector2(5,36),Vector2(7,29),origin+Vector2(3,9),origin,4.0,ha)
	_ellipse(c,origin+Vector2(0,1),Vector2(8.8,10.4),Color(0.11,0.26,0.13,ha))
	for i in range(9,0,-1):
		_ellipse(c,origin+Vector2(-1.7,-0.5),Vector2(7,8.5)*(float(i)/9),Color(0.38,0.59,0.28,ha*0.09))
	for i in range(4):
		var x := -7.0+i*4.8
		var length: float = [18.0,24.0,23.0,17.0][i] * e + reach
		var curl := sin(time*1.2+i*0.6)*0.6
		var root := origin+Vector2(x,-5.0+absf(x)*0.25)
		var end := origin+Vector2(x-3.5,-length+3+curl)
		_limb(c,root,root+Vector2(-1,-length*0.65),end+Vector2(5,-4),end,2.0 if i in [0,3] else 2.2,ha)
		var nail := PackedVector2Array([end+Vector2(-1.1,-0.5),end+Vector2(1.2,0.2),end+Vector2(0.2,3.0),end+Vector2(-3.2,7.5),end+Vector2(-2.3,2.0)])
		c.draw_colored_polygon(nail,Color(0.63,0.71,0.42,ha))
		c.draw_polyline(PackedVector2Array([end+Vector2(-0.7,0),end+Vector2(-0.9,2.7),end+Vector2(-3.2,7.5)]),Color(0.92,0.94,0.68,ha),0.65,true)
		_curve(c,root+Vector2(0,1),root+Vector2(2,4),origin+Vector2(x*0.4,6),origin+Vector2(1,9),Color(0.095,0.27,0.13,ha*0.7),0.45)
	# Opposable thumb hooks across the frame edge rather than reading as a fifth stripe.
	var thumb_end := origin+Vector2(-13,-0.5)
	_limb(c,origin+Vector2(-4,5),origin+Vector2(-15,8),origin+Vector2(-18,-1),thumb_end,2.8,ha)
	_poly(c,[thumb_end+Vector2(-1,-1),thumb_end+Vector2(1,0),thumb_end+Vector2(4,-6),thumb_end+Vector2(-1,-3)],Color(0.83,0.86,0.56,ha))
	_curve(c,origin+Vector2(-5,4),origin+Vector2(-1,1),origin+Vector2(2,3),origin+Vector2(5,6),Color(0.07,0.22,0.10,ha),0.5)

func _torn_half(c: CanvasItem, side: float, split: float, alpha: float, time: float) -> void:
	var shift := side*split
	var fall := split*split*0.005
	var cloth := PackedVector2Array()
	cloth.append(Vector2(shift+side*26,-35+fall))
	cloth.append(Vector2(shift+side*26,35+fall))
	for i in range(19):
		var y := 35.0-i*70.0/18
		cloth.append(Vector2(shift+sin(i*2.7)*2.8+side*sin(i*0.7+time)*split*0.12,y+fall))
	c.draw_colored_polygon(cloth,Color(0.24,0.19,0.16,alpha))
	for i in range(2,cloth.size()-1):
		c.draw_line(cloth[i],cloth[i+1],Color(0.73,0.58,0.39,alpha*0.75),0.65,true)
		c.draw_line(cloth[i],cloth[i]+Vector2(-side*2,1.0),Color(0.61,0.49,0.33,alpha*0.6),0.25,true)
	for i in range(15):
		var y := -31.0+i*4.4+fall
		c.draw_line(Vector2(shift+side*25,y),Vector2(shift+side*(4+sin(i)*2),y+sin(i)*1.3),Color(0.43,0.33,0.22,alpha*0.22),0.3,true)
	var outer := shift+side*30
	_poly(c,[Vector2(outer-4,-43+fall),Vector2(outer+4,-41+fall),Vector2(outer+3,43+fall),Vector2(outer-4,41+fall)],Color(0.35,0.16,0.065,alpha))
	for x in [-2.0,0.0,2.0]: c.draw_line(Vector2(outer+x,-40+fall),Vector2(outer+x,40+fall),Color(0.59,0.34,0.13,alpha*0.6),0.5)
	for y in [-39.0,39.0]:
		_poly(c,[Vector2(shift,y-4+fall),Vector2(shift+side*34,y-4+fall),Vector2(shift+side*34,y+4+fall),Vector2(shift+side*2,y+4+fall),Vector2(shift+side*5,y+1+fall)],Color(0.40,0.20,0.075,alpha))
		c.draw_line(Vector2(shift+side*3,y-2+fall),Vector2(shift+side*32,y-2+fall),Color(0.70,0.44,0.18,alpha),0.65,true)

func _destruction(c: CanvasItem, p: float, alpha: float) -> void:
	var crack_alpha := smoothstep(0.0,0.22,p)*alpha*(1.0-smoothstep(0.30,0.58,p))
	var crack := PackedVector2Array([Vector2(-8,-44),Vector2(-3,-31),Vector2(-10,-20),Vector2(1,-9),Vector2(-4,3),Vector2(6,14),Vector2(-1,28),Vector2(5,44)])
	c.draw_polyline(crack,Color(0.015,0.01,0.02,crack_alpha),1.5,true)
	for i in range(1,crack.size()-1):
		var sign_x := -1.0 if i%2==0 else 1.0
		c.draw_polyline(PackedVector2Array([crack[i],crack[i]+Vector2(sign_x*5,-3),crack[i]+Vector2(sign_x*8,-2)]),Color(0.025,0.013,0.016,crack_alpha),0.65,true)
	# Splintered wood and soft gray particulate have separate sizes and trajectories.
	for i in range(48):
		var birth := 0.32+float(i%9)*0.024
		var age := maxf(0,p-birth)
		if age<=0: continue
		var direction := Vector2(sin(i*2.399),cos(i*1.771))
		var point := Vector2(sin(i*3.1)*27,cos(i*2.7)*36)+direction*age*(32+i%7*5)+Vector2(0,age*age*55)
		var floor_fade := 1.0-smoothstep(43.0,58.0,point.y)
		var opacity := (1.0-smoothstep(0.65,1.0,p))*0.5*floor_fade
		if i%4==0:
			var axis := Vector2.from_angle(i+age*4)
			var normal := Vector2(-axis.y,axis.x)
			_poly(c,[point-axis*3,point+normal*0.8,point+axis*4,point-normal*0.5],Color(0.45,0.27,0.12,alpha*floor_fade))
			c.draw_line(point-axis*2,point+axis*3,Color(0.79,0.56,0.28,alpha*floor_fade),0.3,true)
		else:
			var radius := 0.6+float(i%5)*0.23+age*3
			for layer in range(3,0,-1):
				_ellipse(c,point,Vector2(radius,radius*0.75)*float(layer)*0.65,Color(0.55,0.52,0.56,opacity*0.12))

func _slash(c: CanvasItem, target: Vector2, dimensions: Vector2, p: float) -> void:
	var visibility := smoothstep(0.29,0.40,p)*(1.0-smoothstep(0.61,0.94,p))
	if visibility<=0: return
	var extent := minf(maxf(dimensions.x,dimensions.y)*0.63, 255.0)
	for i in range(3):
		var offset := Vector2((i-1)*extent*0.24,0)
		var a := target+offset+Vector2(extent*0.30,-extent*0.55)
		var b := target+offset+Vector2(-extent*0.47,-extent*0.20)
		var d := target+offset+Vector2(-extent*0.39,extent*0.22)
		var end := target+offset+Vector2(-extent*0.02,extent*0.57)
		for glow in range(3,0,-1):
			_curve(c,a,b,d,end,Color(0.57,0.12,0.80,visibility*0.07),extent*(0.055+glow*0.045))
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var spine := PackedVector2Array()
		var reach := smoothstep(0.29,0.51,p)
		for j in range(25):
			var t := float(j)/24.0*reach
			var point := a.bezier_interpolate(b,d,end,t)
			var tangent := a.bezier_derivative(b,d,end,t).normalized()
			var normal := Vector2(-tangent.y,tangent.x)
			var width := sin(t*PI)*extent*0.032
			left.append(point+normal*width)
			right.append(point-normal*width)
			spine.append(point)
		right.reverse()
		left.append_array(right)
		c.draw_colored_polygon(left,Color(0.56,0.94,0.30,visibility))
		c.draw_polyline(spine,Color(0.91,1.0,0.72,visibility),maxf(0.8,extent*0.007),true)
