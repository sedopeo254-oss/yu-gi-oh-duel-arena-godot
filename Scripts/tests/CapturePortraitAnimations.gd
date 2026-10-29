extends SceneTree

## Optional real-render QA. Not a headless test: run with a display and GL compatibility.
var screen
var output := OS.get_environment("ANIMATION_CAPTURE_DIR")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if output.is_empty(): output = "/tmp/portrait-animation-captures"
	DirAccess.make_dir_recursive_absolute(output)
	screen = load("res://Scenes/presentation/PortraitAnimationDemo.tscn").instantiate()
	root.add_child(screen)
	screen.auto_play = false
	screen.director.set_process(false)
	await process_frame
	for step in range(5):
		screen._next()
		screen.director._process(0.001)
		if step == 4:
			# The actual counterattack resolves before Portrait's destruction.
			screen.director._process(1.0)
			screen.director._process(0.001)
		for progress in [0.12, 0.48, 0.78]:
			var profile = screen.director.registry.profile_for(screen.director.active["card"])
			screen.director._elapsed = profile.duration(screen.director.active["action"]) * progress
			screen.director.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var filename := "%s/%d-%02d.png" % [output, step, int(progress * 100)]
			var err := root.get_texture().get_image().save_png(filename)
			if err != OK:
				push_error("Capture failed: %s (%d)" % [filename, err])
				quit(1)
				return
		screen.director.skip()
	print("Captured 15 animation frames to ", output)
	screen.free()
	quit()
