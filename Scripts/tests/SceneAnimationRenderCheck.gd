extends SceneTree

## Draw-path smoke test: behavior assertions alone do not execute all procedural geometry.
## Logger captures renderer/script/shader failures, including invalid polygon triangulation.
class ErrorCollector extends Logger:
	var count := 0
	var messages: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		mutex.lock()
		count += 1
		if messages.size() < 8: messages.append("%s:%d %s %s" % [file, line, code, rationale])
		mutex.unlock()

var collector := ErrorCollector.new()
var checks := 0
var failures: Array[String] = []
var draw_samples := 0

func _initialize() -> void:
	OS.add_logger(collector)
	_run.call_deferred()

func _run() -> void:
	var screen = load("res://Scenes/presentation/PortraitAnimationDemo.tscn").instantiate()
	root.add_child(screen)
	screen.auto_play = false
	screen._sound.set_enabled(false)
	screen.director.set_process(false)
	await process_frame
	_check(screen._sound._cues.size() == 4, "four original synthesized cues prepared")
	for cue in screen._sound._cues.values():
		_check(cue.data.size() > 22050, "audio cue has actual PCM data")
		var peak := 0
		for sample in range(0, cue.data.size(), 2): peak = maxi(peak, absi(cue.data.decode_s16(sample)))
		_check(peak > 100 and peak < 32767, "synthesized cue is non-silent and avoids clipping")
	for step in range(5):
		screen._next()
		_check(screen.scenario.error.is_empty(), "showcase step remains legal")
		var jobs := 0
		while screen.director.is_busy() and jobs < 8:
			jobs += 1
			screen.director._process(0.0)
			var profile = screen.director.registry.profile_for(screen.director.active["card"])
			var duration: float = profile.duration(screen.director.active["action"])
			for sample in range(26):
				screen.director._elapsed = duration * float(sample) / 25.0
				screen.director._clock = sample * 0.17
				screen.director.queue_redraw()
				await process_frame
				draw_samples += 1
			screen.director._process(duration + 0.01)
		_check(jobs < 8, "showcase queue completes")
	_check(screen.scenario.portrait.zone == Enums.Zone.GRAVEYARD, "showcase finishes with true battle destruction")
	screen._restart()
	screen._next()
	screen.director._process(0.1)
	screen._restart()
	_check(not screen.director.is_busy() and screen.scenario.step == 0, "replay interrupts old timeline cleanly")
	screen.director.set_reduced_motion(true)
	screen._backdrop.reduced_motion = true
	screen._next()
	await process_frame
	_check(not screen.director.is_busy(), "motion reduction skips cinematic cues")
	var old_time: float = screen._backdrop._time
	await process_frame
	_check(screen._backdrop._time == old_time, "motion reduction freezes atmospheric particles and shader time")
	screen.free()
	await process_frame
	await process_frame
	_check(collector.count == 0, "no renderer/script/shader errors across draw samples")
	for message in collector.messages: failures.append(message)
	OS.remove_logger(collector)
	print("Animation rendering: %d assertions, %d draw samples, %d errors" % [checks, draw_samples, collector.count])
	for failure in failures: print("FAIL: ", failure)
	print("RESULT: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
