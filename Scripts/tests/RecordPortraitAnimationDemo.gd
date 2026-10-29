extends SceneTree

## Use Godot --write-movie /tmp/portrait-study.avi --fixed-fps 30 with this script.
## Quit only after every real-event animation finishes; release audio before shutdown.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var screen = load("res://Scenes/presentation/PortraitAnimationDemo.tscn").instantiate()
	root.add_child(screen)
	var ending := 0
	var completed := false
	for frame in range(4000):
		await process_frame
		if screen.scenario.step == 5 and not screen.director.is_busy():
			ending += 1
			if ending >= 45:
				completed = true
				break
	var error: String = screen.scenario.error
	screen.free()
	# AudioServer retires playback on its mixer thread; allow that retirement before quit.
	await create_timer(0.15).timeout
	await process_frame
	print("Portrait recording: ", "PASS" if completed and error.is_empty() else "FAIL", " ", error)
	quit(0 if completed and error.is_empty() else 1)
