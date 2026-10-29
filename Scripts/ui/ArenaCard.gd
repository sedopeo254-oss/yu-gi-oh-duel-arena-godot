class_name ArenaCard
extends Button

## A vector-only card face. Identity comes exclusively from the viewer's delivered snapshot.
var card: Dictionary = {}
var accent := Color("58d9d0")
var highlighted := false
var compact := false
var category := ""

func configure(data: Dictionary, tint: Color, is_compact: bool = false, kind: String = "") -> void:
	card = data.duplicate(true)
	accent = tint
	compact = is_compact
	category = kind
	custom_minimum_size = Vector2(100, 110) if compact else Vector2(130, 172)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Face-down card" if bool(card.get("hidden", true)) else str(card.get("name", ""))
	flat = true
	queue_redraw()

func _ready() -> void:
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var hidden := bool(card.get("hidden", true))
	var color := accent
	if not hidden:
		if category == "Spell": color = Color("58c7ae")
		elif category == "Trap": color = Color("ce8ac9")
		else: color = Color("dcb777")
	var bright := highlighted or is_hovered() or has_focus()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("152237") if hidden else Color("202938")
	box.border_color = color if bright else color.darkened(0.48)
	box.set_border_width_all(2 if bright else 1)
	box.set_corner_radius_all(6)
	draw_style_box(box, r)
	var font := ThemeDB.fallback_font
	if hidden:
		var center := r.get_center()
		for factor in [0.78, 0.58, 0.35]:
			var w: float = r.size.x * factor * 0.48
			var h: float = r.size.y * factor * 0.42
			draw_polyline(PackedVector2Array([center + Vector2(0, -h), center + Vector2(w, 0),
				center + Vector2(0, h), center + Vector2(-w, 0), center + Vector2(0, -h)]),
				Color(color, 0.65), 1.5, true)
		draw_circle(center, 5, color)
		return
	var top := 34.0 if compact else 48.0
	var art := Rect2(11, top, size.x - 22, size.y * (0.31 if compact else 0.42))
	draw_rect(art, color.darkened(0.78))
	var center := art.get_center()
	# Neutral faceted diamond: deliberately no stars, seals, or occult symbols.
	var w := art.size.y * 0.34
	var h := art.size.y * 0.40
	var top_point := center + Vector2(0, -h)
	var right_point := center + Vector2(w, 0)
	var bottom_point := center + Vector2(0, h)
	var left_point := center + Vector2(-w, 0)
	draw_polyline(PackedVector2Array([top_point, right_point, bottom_point, left_point, top_point]),
		Color(color, 0.82), 1.6, true)
	draw_line(top_point, center + Vector2(w * 0.28, 0), Color(color, 0.50), 1.2, true)
	draw_line(center + Vector2(w * 0.28, 0), bottom_point, Color(color, 0.50), 1.2, true)
	draw_line(left_point, right_point, Color(color, 0.50), 1.2, true)
	var name_text := str(card.get("name", "Card"))
	var words := name_text.split(" ")
	var lines: Array[String] = [""]
	var font_size := 13 if compact else 15
	for word in words:
		var current := lines[lines.size() - 1]
		if font.get_string_size(current + " " + word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 20 and current != "":
			lines.append(word)
		else:
			lines[lines.size() - 1] = (current + " " + word).strip_edges()
	for i in range(mini(2, lines.size())):
		draw_string(font, Vector2(10, 20 + i * (font_size + 1)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, font_size, Color("edf2f4"))
	var tag := category.to_upper()
	if card.has("level"):
		tag = "LV %d  /  %s" % [int(card["level"]), str(card.get("attribute", ""))]
	draw_string(font, Vector2(11, art.end.y + 17), tag, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 10, color)
	if card.has("atk"):
		draw_string(font, Vector2(11, size.y - 12), "%s / %s" % [card["atk"], card.get("def", 0)],
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 12, Color("f2e9d7"))
	elif not bool(card.get("face_up", false)) and int(card.get("zone", -1)) != 1:
		draw_string(font, Vector2(11, size.y - 12), "SET · PRIVATE", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 10, color)
	if int(card.get("position", -1)) in [1, 2] and int(card.get("zone", -1)) == 2:
		draw_rect(Rect2(size.x - 9, 11, 3, size.y - 22), color)
