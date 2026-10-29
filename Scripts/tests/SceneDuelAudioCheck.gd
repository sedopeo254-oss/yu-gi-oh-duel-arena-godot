extends SceneTree

const Sound = preload("res://Scripts/presentation/DuelAudio.gd")
const Bank = preload("res://Scripts/presentation/DuelSoundBank.gd")
const Scenario = preload("res://Scripts/presentation/demo/PortraitAnimationScenario.gd")
var checks := 0
var failures: Array[String] = []
var director: CardAnimationDirector
var sound
var heard: Array[String] = []
var playback_refs: Array[WeakRef] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_sound_bank_checks()
	_preferences_checks()
	director = CardAnimationDirector.new()
	root.add_child(director)
	director.set_process(false)
	sound = Sound.new()
	sound.persist_preferences = false
	root.add_child(sound)
	director.animation_started.connect(sound.play_cue)
	director.animation_finished.connect(sound.finish_cue)
	director.playback_cancelled.connect(sound.stop)
	sound.cue_started.connect(func(action):
		heard.append(action)
		playback_refs.append(weakref(sound._voice.get_stream_playback())))
	_real_events_check()
	_privacy_checks()
	_settings_and_interruptions_check()
	sound.free()
	director.free()
	await _board_check()
	# Stop detaches the stream immediately; the audio mixer retires its playback later.
	await create_timer(1.1).timeout
	await process_frame
	_check(playback_refs.all(func(ref): return ref.get_ref() == null), "all actual mixer playback resources retire after stop/free")
	print("Duel audio: %d assertions" % checks)
	for failure in failures: print("FAIL: ", failure)
	print("RESULT: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _sound_bank_checks() -> void:
	var buffers: Array = []
	for action in Bank.DURATIONS:
		var cue: AudioStreamWAV = Bank.synthesize(action)
		_check(cue.format == AudioStreamWAV.FORMAT_16_BITS and cue.mix_rate == Bank.RATE and not cue.stereo, "%s format" % action)
		_check(cue.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s never loops" % action)
		_check(cue.data.size() == int(Bank.DURATIONS[action] * Bank.RATE) * 2, "%s finite timeline-aligned PCM length" % action)
		var peak := 0
		var energy := 0.0
		for i in range(0, cue.data.size(), 2):
			var sample := cue.data.decode_s16(i)
			peak = maxi(peak, absi(sample))
			energy += pow(float(sample) / 32767.0, 2.0)
		_check(peak > 1000 and peak < 30000 and energy > 1.0, "%s audible PCM with headroom" % action)
		_check(cue.data.decode_s16(0) == 0 and cue.data.decode_s16(cue.data.size() - 2) == 0, "%s smooth silent endpoints" % action)
		_check(cue.data == Bank.synthesize(action).data, "%s local seeded synthesis is repeatable" % action)
		_check(not buffers.has(cue.data), "%s distinct sound" % action)
		buffers.append(cue.data)
	_check(Bank.synthesize("private_response") == null, "unknown events have no fabricated sound")
	var replacement := AudioStreamWAV.new()
	var replaceable = Sound.new()
	replaceable.persist_preferences = false
	replaceable.cue_overrides["attack"] = replacement
	root.add_child(replaceable)
	_check(replaceable._cues["attack"] == replacement and replaceable._cues.size() == 4, "rights-cleared resource replacement preserves other synthesized cues")
	replaceable.free()

func _preferences_checks() -> void:
	var path := "user://audio_test_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var first = Sound.new()
	first.settings_path = path
	root.add_child(first)
	_check(first.enabled and is_equal_approx(first.volume, Sound.DEFAULT_VOLUME), "missing settings use conservative defaults")
	first.set_volume(0.23)
	first.set_enabled(false)
	_check(first.last_save_error == OK, "settings save succeeds")
	first.free()
	var second = Sound.new()
	second.settings_path = path
	root.add_child(second)
	_check(not second.enabled and is_equal_approx(second.volume, 0.23), "mute and volume survive a fresh audio node")
	second.set_volume(1.5)
	_check(second.volume == 1.0, "volume clamps high")
	second.set_volume(-2.0)
	_check(second.volume == 0.0, "volume clamps low")
	second.set_volume(NAN)
	_check(is_equal_approx(second.volume, Sound.DEFAULT_VOLUME), "nonfinite volume is not passed to mixer")
	var config := ConfigFile.new()
	config.set_value("effects", "enabled", "not a boolean")
	config.set_value("effects", "volume", "not a number")
	config.save(path)
	second.load_preferences()
	_check(second.enabled and is_equal_approx(second.volume, Sound.DEFAULT_VOLUME), "malformed preferences use defaults safely")
	second.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _real_events_check() -> void:
	var scenario = Scenario.new()
	director.ingest(0, [], scenario.snapshot())
	director.present(0)
	for i in range(5):
		scenario.advance()
		_check(scenario.error.is_empty(), "real action %d accepted by engine" % i)
		director.ingest(0, scenario.drain(), scenario.snapshot())
		director.present(0)
		_drain()
	_check(heard == ["summon", "position", "position", "attack", "destroy", "attack", "destroy"], "real summon, both positions, two attacks and actual destructions drive ordered audio once")
	_check(scenario.portrait.zone == Enums.Zone.GRAVEYARD, "destruction audio corresponds to actual battle destruction")
	_check(not director.is_busy(), "audio never holds the engine or animation queue open")
	_check(not sound._voice.playing and sound._voice.stream == null, "timeline completion stops and releases its cue")

func _privacy_checks() -> void:
	director.reset()
	heard.clear()
	var snapshot := _snapshot()
	var attack := {"kind": "ATTACK_DECLARED", "data": {"attacker_id": 42}}
	director.ingest(1, [attack], snapshot)
	_check(heard.is_empty() and not sound._voice.playing, "other viewer's event alone is inaudible")
	director.present(0)
	director._process(0.1)
	_check(heard.is_empty(), "current viewer never hears other viewer pending audio")
	director.present(1)
	director._process(0.1)
	_check(heard == ["attack"] and sound._voice.playing, "authorized reveal starts that viewer's public cue")
	director.conceal()
	_check(not sound._voice.playing and sound._voice.stream == null, "cover stops and releases active audio immediately")
	director.present(1)
	director._process(0.1)
	_check(heard == ["attack"], "uncover does not replay cancelled audio")
	director.reset()
	director.ingest(0, [attack], snapshot)
	director.present(0)
	director._process(0.1)
	var hidden := _snapshot()
	hidden["players"][0]["monster_zones"][0] = {"id": -55, "hidden": true, "face_up": false, "name": "Planted private name"}
	director.ingest(0, [attack], hidden)
	_check(not sound._voice.playing and director.active.is_empty(), "hidden snapshot stops old public audio without joining opaque handles")
	var count := heard.size()
	director.present(0)
	_drain()
	_check(heard.size() == count, "hidden card with planted identity remains silent")
	snapshot["players"][0]["monster_zones"][0]["face_up"] = false
	director.ingest(0, [attack], snapshot)
	director.present(0)
	_drain()
	_check(heard.size() == count, "owner-known face-down card remains silent")
	director.ingest(0, [{"kind": "NORMAL_SUMMON_DECLARED", "data": {"card_id": 42}},
		{"kind": "SUMMON_NEGATED", "data": {"card_id": 42}},
		{"kind": "CARD_MOVED", "data": {"card_id": 42}},
		{"kind": "RESPONSE_PASSED", "data": {"player": 1}}], _snapshot())
	director.present(0)
	_drain()
	_check(heard.size() == count, "negated summon, non-destruction moves and response timing are silent")
	director.reset()
	director.ingest(0, [{"kind": "BATTLE_POSITION_CHANGED", "data": {"card_id": 42, "to": 0}},
		{"kind": "FLIP_SUMMON_SUCCEEDED", "data": {"card_id": 42}}], _snapshot())
	director.present(0)
	director.present(0)
	_drain()
	_check(heard.size() == count + 1 and heard.back() == "summon", "Flip Summon and repeated renders produce one sound, not duplicates")

func _settings_and_interruptions_check() -> void:
	_start_attack()
	_check(sound._voice.playing, "active cue before mute")
	sound.set_enabled(false)
	_check(not sound._voice.playing, "mute cancels immediately")
	var count := heard.size()
	_start_attack()
	_check(heard.size() == count, "muted action never enters audio queue")
	sound.set_enabled(true)
	_check(not sound._voice.playing, "unmute never replays old events")
	_start_attack()
	sound.set_volume(0.0)
	_check(not sound._voice.playing, "zero volume stops voice")
	_start_attack()
	_check(not sound._voice.playing, "zero volume suppresses new voice")
	sound.set_volume(0.30)
	_check(not sound._voice.playing, "restoring volume never resumes old voice")
	_start_attack()
	_check(is_equal_approx(db_to_linear(sound._voice.volume_db), 0.30 * Sound.OUTPUT_GAIN), "volume reaches actual mixer gain")
	director.set_reduced_motion(true)
	_check(not sound._voice.playing, "reduced motion cancels audio as well as visual cue")
	count = heard.size()
	_start_attack()
	_check(heard.size() == count and not sound._voice.playing, "reduced motion suppresses new cues")
	director.set_reduced_motion(false)
	_check(not sound._voice.playing, "restoring motion never replays skipped events")
	_start_attack()
	director.present(1)
	_check(not sound._voice.playing, "direct viewer switch stops previous viewer audio")
	_start_attack()
	director.skip()
	_check(not sound._voice.playing, "skip stops active audio")
	_start_attack()
	director.reset()
	_check(not sound._voice.playing and not director.is_busy() and is_equal_approx(sound.volume, 0.30), "restart clears playback while preserving volume")
	_start_attack()
	var moved := _snapshot()
	moved["players"][0]["monster_zones"] = [null, moved["players"][0]["monster_zones"][0]]
	director.ingest(0, [], moved)
	_check(not sound._voice.playing, "stale source slot cancels sound with animation")

func _board_check() -> void:
	# Headless SceneTree defaults to 64x64; exercise a supported production viewport.
	root.size = Vector2i(1600, 900)
	var board = load("res://Scenes/ui/DuelBoard.tscn").instantiate()
	root.add_child(board)
	# Never rewrite the real user's config during tests.
	board._sound.persist_preferences = false
	board._animations.set_reduced_motion(false)
	board._sound.set_enabled(true)
	board._sound.set_volume(0.60)
	var events: Array[String] = []
	board._sound.cue_started.connect(func(action):
		events.append(action)
		playback_refs.append(weakref(board._sound._voice.get_stream_playback())))
	var did_summon := false
	for i in range(1000):
		await process_frame
		if board.current.is_empty(): continue
		if board.handoff_required: board.reveal_board()
		if events.has("summon"): break
		for button in board._choices.get_children():
			if button is Button and button.text.begins_with("Normal Summon") and not did_summon:
				did_summon = true
				button.pressed.emit()
				break
			elif button is Button and (button.text.begins_with("Proceed") or button.text.begins_with("Pass")):
				button.pressed.emit()
				break
	_check(events.has("summon"), "actual production board/session summon produces sound")
	board._audio_button.pressed.emit()
	await process_frame
	_check(board._audio_dialog.visible, "header opens volume settings")
	_check(Rect2(Vector2.ZERO, board.size).encloses(board._audio_button.get_global_rect()), "sound button fits within production board viewport")
	_check(board._audio_slider.size.x >= 180, "volume slider remains usable after settings layout")
	board._audio_slider.value = 34
	_check(is_equal_approx(board._sound.volume, 0.34) and board._audio_value.text == "34%", "slider updates actual gain and value label")
	board._audio_toggle.button_pressed = false
	_check(not board._sound.enabled and not board._sound._voice.playing and board._audio_button.text == "Sound off", "UI mute stops and indicates audio state")
	board._audio_dialog.hide()
	board._audio_button.pressed.emit()
	_check(not board._audio_toggle.button_pressed and is_equal_approx(board._audio_slider.value, 34), "reopening settings retains selection")
	board._audio_dialog.hide()
	board.cover_board()
	_check(not board._sound._voice.playing, "board cover wiring is silent")
	board.start_new_duel()
	_check(not board._sound.enabled and is_equal_approx(board._sound.volume, 0.34), "new duel retains sound preferences")
	board.free()

func _start_attack() -> void:
	director.reset()
	director.ingest(0, [{"kind": "ATTACK_DECLARED", "data": {"attacker_id": 42}}], _snapshot())
	director.present(0)
	director._process(0.1)

func _snapshot() -> Dictionary:
	return {"players": [{"id": 0, "monster_zones": [{"id": 42, "hidden": false, "face_up": true, "name": "Public monster", "position": 0}]}, {"id": 1, "monster_zones": []}]}

func _drain() -> void:
	for i in range(120):
		if not director.is_busy(): return
		director._process(0.1)
	_check(false, "finite timeline drain")

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description)
