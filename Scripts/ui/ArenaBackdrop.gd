extends Control

## Original procedural arena, without any external game assets.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("09111e"))
	var center := size * Vector2(0.50, 0.48)
	for i in range(8):
		var radius := 110.0 + i * 76.0
		draw_arc(center, radius, 0, TAU, 100, Color(0.15, 0.38, 0.44, 0.10), 1.0, true)
	for x in range(0, int(size.x), 56):
		draw_line(Vector2(x, 0), Vector2(x - 240, size.y), Color(0.22, 0.37, 0.47, 0.035))
	draw_line(Vector2(0, 0), Vector2(size.x, 0), Color("59d8cf"), 3)
