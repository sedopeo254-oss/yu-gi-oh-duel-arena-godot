extends Control

## Original, static architectural arena. No downloaded art or symbolic/occult motifs.
## Deliberately static: reduced-motion users never inherit decorative background motion.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("07121d"))
	# Broad layered light, rather than a noisy repeating texture behind the cards.
	for i in range(28):
		var t := float(i) / 28.0
		var color := Color("102b39").lerp(Color("07121d"), t)
		draw_rect(Rect2(0, size.y * t, size.x, size.y / 28.0 + 1), color)
	var horizon := size.y * 0.48
	for i in range(13):
		var x := size.x * float(i) / 12.0
		draw_line(Vector2(size.x * 0.5 + (x - size.x * 0.5) * 0.2, horizon),
			Vector2(x, size.y), Color(0.29, 0.59, 0.65, 0.055), 1.0, true)
	for i in range(8):
		var t := float(i) / 7.0
		var y := horizon + (size.y - horizon) * t * t
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.29, 0.59, 0.65, 0.045))
	# Quiet architectural corner accents frame the play space.
	for side in [0, 1]:
		var x := 0.0 if side == 0 else size.x
		var direction := 1.0 if side == 0 else -1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + direction * size.x * 0.15, 0),
			Vector2(x + direction * size.x * 0.04, size.y * 0.32), Vector2(x, size.y * 0.4)]), Color(0.30, 0.61, 0.65, 0.045))
	draw_line(Vector2(0, 0), Vector2(size.x, 0), Color("69d8ca"), 2)
