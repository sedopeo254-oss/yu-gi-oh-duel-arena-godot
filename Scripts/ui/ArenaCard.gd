class_name ArenaCard
extends Button

## Original category illustrations. Hidden cards never select art or text by identity.
var card: Dictionary = {}
var accent := Color("69d8ca")
var highlighted := false
var compact := false
var category := ""

func configure(data: Dictionary, tint: Color, is_compact: bool = false, kind: String = "") -> void:
	card = data.duplicate(true)
	accent = tint
	compact = is_compact
	category = kind
	custom_minimum_size = Vector2(90, 100) if compact else Vector2(138, 146)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Face-down card" if bool(card.get("hidden", true)) else str(card.get("name", ""))
	if not bool(card.get("hidden", true)) and int(card.get("position", -1)) in [1, 2] and int(card.get("zone", -1)) == 2:
		tooltip_text += " · Defense position"
	if not bool(card.get("hidden", true)) and card.has("atk"):
		tooltip_text += " · ATK %s · DEF %s" % [card["atk"], card.get("def", 0)]
	flat = true
	queue_redraw()

func _ready() -> void:
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var hidden := bool(card.get("hidden", true))
	var color := accent
	if not hidden:
		if category == "Spell": color = Color("79d5b8")
		elif category == "Trap": color = Color("cba7e4")
		else: color = Color("e2bc7f")
	var bright := highlighted or is_hovered() or has_focus()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("142634") if hidden else Color("172432")
	box.border_color = color if bright else color.darkened(0.38)
	box.set_border_width_all(2 if bright else 1)
	box.set_corner_radius_all(7)
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0, 2)
	draw_style_box(box, r)
	var font := ThemeDB.fallback_font
	if hidden:
		_draw_back(r, color)
		return
	# Compact art coordinates stay aligned with CardAnimationDirector's actor anchors.
	var top := 34.0 if compact else 48.0
	var art := Rect2(11, top, size.x - 22, size.y * (0.31 if compact else (0.58 if size.y > 250 else 0.42)))
	_draw_illustration(art, color)
	var name_text := str(card.get("name", "Card"))
	var lines: Array[String] = [""]
	var font_size := (10 if size.x < 80 else 12) if compact else 15
	for word in name_text.split(" "):
		var current := lines[lines.size() - 1]
		if font.get_string_size(current + " " + word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 20 and current != "":
			lines.append(word)
		else:
			lines[lines.size() - 1] = (current + " " + word).strip_edges()
	for i in range(mini(2, lines.size())):
		var line := lines[i]
		if i == 1 and lines.size() > 2: line += "…"
		line = _fit_text(line, font, font_size, size.x - 20)
		draw_string(font, Vector2(10, 18 + i * (font_size + 1)), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, font_size, Color("f3f4ed"))
	var tag := category.to_upper()
	if card.has("level"):
		tag = "L%d  %s" % [int(card["level"]), str(card.get("attribute", ""))]
	var narrow_stats := compact and size.x < 80 and card.has("atk")
	if not narrow_stats:
		draw_string(font, Vector2(11, art.end.y + 13), tag, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 9 if compact else 10, color)
	if card.has("atk"):
		if narrow_stats:
			# Preserve all digits on touch-sized field cards; never silently clip DEF.
			for i in range(2):
				var stats := ("A %s" % card["atk"]) if i == 0 else ("D %s" % card.get("def", 0))
				draw_string(font, Vector2(10, size.y - 18 + i * 10), stats, HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, 8, Color("f2e9d7"))
		else:
			var stats := "%s / %s" % [card["atk"], card.get("def", 0)] if compact else "ATK %s   DEF %s" % [card["atk"], card.get("def", 0)]
			draw_string(font, Vector2(11, size.y - 10), stats, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 11 if compact else 10, Color("f2e9d7"))
	elif not bool(card.get("face_up", false)) and int(card.get("zone", -1)) != 1:
		draw_string(font, Vector2(11, size.y - 10), "SET" if compact and size.x < 80 else "SET · PRIVATE", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 9, color)
	if int(card.get("position", -1)) in [1, 2] and int(card.get("zone", -1)) == 2:
		draw_rect(Rect2(size.x - 9, 11, 3, size.y - 22), color)

func _draw_back(r: Rect2, color: Color) -> void:
	var inset := r.grow(-5)
	draw_rect(inset, Color(color, 0.25), false, 1)
	# Woven diagonal bands, not a symbol, seal or copied card-back design.
	for i in range(5):
		var t := float(i + 1) / 6.0
		var y := lerpf(inset.position.y, inset.end.y, t)
		draw_line(Vector2(inset.position.x, y), Vector2(inset.end.x, y - inset.size.y * 0.12), Color(color, 0.14), 2, true)
	var center := r.get_center()
	var length := minf(r.size.x * 0.38, 25)
	for offset in [-4.0, 4.0]:
		draw_line(center + Vector2(-length, offset), center + Vector2(length, offset), Color(color, 0.75), 1.5, true)

func _draw_illustration(art: Rect2, color: Color) -> void:
	draw_rect(art, color.darkened(0.83))
	var center := art.get_center()
	var h := art.size.y
	var w := art.size.x
	# The variation depends only on an already-visible name, never on private IDs.
	var variant := absi(str(card.get("name", "")).hash()) % 3
	if category == "Spell":
		# Layered winds over distant water.
		for i in range(4):
			var y := art.position.y + h * (0.22 + i * 0.18)
			var points := PackedVector2Array()
			for j in range(15):
				var x := float(j) / 14.0
				points.append(Vector2(art.position.x + x * w, y + sin(x * 5.0 + i + variant) * h * 0.08))
			draw_polyline(points, Color(color, 0.25 + i * 0.12), 1.5, true)
	elif category == "Trap":
		# A faceted protective shield against architectural panels.
		for i in range(4):
			draw_rect(Rect2(art.position + Vector2(w * i * 0.25 + 2, 2), Vector2(w * 0.22, h - 4)), Color(color, 0.08))
		var points := PackedVector2Array([center + Vector2(-h * 0.27, -h * 0.30), center + Vector2(h * 0.27, -h * 0.30),
			center + Vector2(h * 0.22, h * 0.10), center + Vector2(0, h * 0.35), center + Vector2(-h * 0.22, h * 0.10)])
		draw_colored_polygon(points, Color(color, 0.3))
		points.append(points[0])
		draw_polyline(points, Color(color, 0.8), 1.4, true)
		draw_line(center + Vector2(0, -h * 0.23), center + Vector2(0, h * 0.22), Color(color, 0.6), 1.2, true)
	else:
		# An original alpine vista, with daylight, layered peaks and a clean silhouette.
		draw_circle(art.position + Vector2(w * (0.68 - variant * 0.14), h * 0.25), h * 0.12, Color(color, 0.65))
		for layer in range(2):
			var points := PackedVector2Array([Vector2(art.position.x, art.end.y)])
			for i in range(6):
				var x := float(i) / 5.0
				var y := h * (0.38 + float((i + variant + layer) % 3) * 0.16 + layer * 0.1)
				points.append(art.position + Vector2(x * w, y))
			points.append(art.end)
			draw_colored_polygon(points, color.darkened(0.54 - layer * 0.13))
	draw_rect(art, Color(color, 0.25), false, 1)

func _fit_text(value: String, font: Font, font_size: int, width: float) -> String:
	var fitted := value
	while fitted.length() > 1 and font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		fitted = fitted.substr(0, fitted.length() - 2) + "…"
	return fitted
