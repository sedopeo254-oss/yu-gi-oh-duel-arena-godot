extends SceneTree

## Render-only QA helper. Run with a real display and --rendering-method gl_compatibility.
## Outputs go to user://arena-previews, or DUEL_ARENA_PREVIEW_DIR when set.
var screen
var output_dir := ""
var frames := 0
var captured := false
var summoned := false
var summoned_click := false
func _initialize() -> void:
	output_dir = OS.get_environment("DUEL_ARENA_PREVIEW_DIR")
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("user://arena-previews")
	var error := DirAccess.make_dir_recursive_absolute(output_dir)
	if error != OK:
		push_error("Could not create preview directory: %s" % error_string(error))
		quit(1)
		return
	screen = load("res://Scenes/ui/DuelBoard.tscn").instantiate()
	root.add_child(screen)
func _process(_delta: float) -> bool:
	if captured: return false
	frames += 1
	if frames > 2000:
		captured = true
		quit(1)
		return false
	if screen.current.is_empty(): return false
	if screen.handoff_required: screen.reveal_board()
	for entries in screen.logs:
		for line in entries:
			if "NORMAL_SUMMON_SUCCEEDED" in str(line): summoned = true
	if summoned and screen.viewer == 0 and str(screen.current.get("mode", "")) == "ACTION":
		captured = true
		var own = screen.view["players"][screen.viewer]
		for card in own["monster_zones"]:
			if card != null:
				screen._inspect(card)
				break
		capture.call_deferred()
		return false
	for button in screen._choices.get_children():
		if button is Button and button.text.begins_with("Normal Summon") and not summoned_click:
			summoned_click = true
			button.pressed.emit()
			return false
	for prefix in ["Proceed", "Pass", "No"]:
		for button in screen._choices.get_children():
			if button is Button and button.text.begins_with(prefix):
				button.pressed.emit()
				return false
	return false
func capture() -> void:
	for dimensions in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(390, 844), Vector2i(320, 640)]:
		root.size = dimensions
		screen._sync_window_layout()
		screen._select_tab(0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		print("Board screenshot: ", root.get_texture().get_image().save_png(output_dir.path_join("board-%dx%d.png" % [dimensions.x, dimensions.y])))
		if dimensions.x == 390:
			screen._select_tab(1)
			await process_frame
			await RenderingServer.frame_post_draw
			print("Moves screenshot: ", root.get_texture().get_image().save_png(output_dir.path_join("moves-phone.png")))
			screen._select_tab(2)
			await process_frame
			await RenderingServer.frame_post_draw
			print("Inspector screenshot: ", root.get_texture().get_image().save_png(output_dir.path_join("inspector-phone.png")))
	screen.cover_board()
	await process_frame
	await RenderingServer.frame_post_draw
	print("Cover screenshot: ", root.get_texture().get_image().save_png(output_dir.path_join("cover-phone.png")))
	screen.free()
	# Explicit synthetic rendering fixture, separate from real duel captures.
	root.size = Vector2i(480, 240)
	root.content_scale_size = root.size
	var fixture := Control.new()
	root.add_child(fixture)
	var caption := Label.new()
	caption.text = "STAT LAYOUT FIXTURE · ATK 3000 / DEF 2500"
	caption.position = Vector2(10, 10)
	fixture.add_child(caption)
	var x := 10.0
	for width in [51.2, 59.2, 64.0, 90.0]:
		var card := ArenaCard.new()
		card.configure({"hidden": false, "name": "Visible fixture", "atk": 3000, "def": 2500,
			"level": 8, "attribute": "LIGHT", "position": 0, "zone": 2}, Color("69d8ca"), true, "Monster")
		card.custom_minimum_size = Vector2(width, 96)
		card.size = card.custom_minimum_size
		card.position = Vector2(x, 70)
		fixture.add_child(card)
		x += width + 20
	await process_frame
	await RenderingServer.frame_post_draw
	print("Stat fixture: ", root.get_texture().get_image().save_png(output_dir.path_join("stat-layout-fixture.png")))
	fixture.free()
	quit()
