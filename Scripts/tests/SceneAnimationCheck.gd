extends SceneTree

const Scenario = preload("res://Scripts/presentation/demo/PortraitAnimationScenario.gd")
var checks := 0
var failures: Array[String] = []
var director: CardAnimationDirector

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	director = CardAnimationDirector.new()
	root.add_child(director)
	var scenario = Scenario.new()
	director.ingest(0, [], scenario.snapshot())
	director.present(0)
	_check(scenario.portrait.definition.passcode == "32541773" and scenario.portrait.current_atk() == 1200 and scenario.portrait.current_def() == 1500, "accurate opt-in Portrait fixture")
	var expected := ["summon", "position", "position", "attack", "attack"]
	var portrait_actions: Array = []
	director.animation_started.connect(func(action, card_name):
		if card_name == "The Portrait's Secret": portrait_actions.append(action))
	for i in range(5):
		scenario.advance()
		_check(scenario.error.is_empty(), "scenario action %d legally accepted" % i)
		var snapshot: Dictionary = scenario.snapshot()
		var events: Array = scenario.drain()
		director.ingest(0, events, snapshot)
		_check(not director._pending[0].is_empty(), "real engine events enqueue animation %d" % i)
		_check(director._pending[0][0]["action"] == expected[i], "correct semantic animation %d" % i)
		director.present(0)
		_drain()
	_check(portrait_actions == ["summon", "position", "position", "attack", "destroy"], "Portrait completes all choreography from real engine events")
	_check(scenario.portrait.zone == Enums.Zone.GRAVEYARD, "stronger attacker actually destroys Portrait")
	_check(director.played_counts.get("destroy", 0) == 2, "battle destruction plays for both targets, not CARD_MOVED duplicates")
	_check(not director.is_busy(), "finite animations leave no running job")
	_privacy_and_interruption_checks()
	_registry_checks()
	_duplicate_and_burst_checks()
	_control_change_checks()
	director.free()
	# Check actual board wiring with the asynchronous session, not just fixture projection.
	await _board_check()
	print("Animations: %d assertions" % checks)
	for failure in failures: print("FAIL: ", failure)
	print("RESULT: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _drain() -> void:
	for i in range(80):
		if not director.is_busy(): return
		director._process(0.1)
	_check(false, "animation queue exceeded finite duration")

func _privacy_and_interruption_checks() -> void:
	var visible := {"id": 42, "hidden": false, "face_up": true, "name": "The Portrait's Secret", "position": 0}
	var attack := {"kind": "ATTACK_DECLARED", "data": {"attacker_id": 42, "target_id": -1}}
	var snapshot := {"players": [{"id": 0, "monster_zones": [visible]}, {"id": 1, "monster_zones": []}]}
	director.reset()
	director.ingest(0, [attack], snapshot)
	director.present(0)
	director._process(0.1)
	_check(not director.active.is_empty(), "attack starts before interruption")
	director.conceal()
	_check(director.active.is_empty() and not director.visible and director.active_viewer == -1, "cover immediately clears active effect and hides overlay")
	director.present(0)
	_check(not director.is_busy(), "manual uncover does not replay canceled animation")
	director.ingest(0, [attack], snapshot)
	director.present(0)
	director._process(0.1)
	var hidden := {"id": -55, "hidden": true, "face_up": false, "name": "The Portrait's Secret", "position": 2}
	snapshot["players"][0]["monster_zones"] = [hidden]
	director.ingest(0, [attack], snapshot)
	_check(director.active.is_empty() and director._pending[0].is_empty(), "new hidden snapshot cancels stale identifying artwork, no public-ID to handle join")
	_check(director.registry.profile_for(hidden) == null, "hidden data never selects a profile even with a planted name")
	var private_card := visible.duplicate(true)
	private_card["face_up"] = false
	_check(director.registry.profile_for(private_card) == null, "owner-known set card also has no identifying field actor")
	director.ingest(1, [attack], {"players": [{"id": 0, "monster_zones": [visible]}, {"id": 1, "monster_zones": []}]})
	_check(director._queue.is_empty() and not director._pending[1].is_empty(), "other viewer's pending effects never join current viewer queue")
	director.set_reduced_motion(true)
	director.present(1)
	_check(not director.is_busy(), "reduced motion skips queued effects")
	director.reset()
	_check(director._models == [{}, {}] and director._pending == [[], []] and director.played_counts.is_empty(), "restart clears viewer models, queue, and counters")
	director.set_reduced_motion(false)
	director.ingest(0, [{"kind": "NORMAL_SUMMON_DECLARED", "data": {"card_id": 42}}, {"kind": "SUMMON_NEGATED", "data": {"card_id": 42}}], {"players": [{"id": 0, "monster_zones": [visible]}]})
	_check(director._pending[0].is_empty(), "negated declaration is not a successful summon animation")
	director.ingest(0, [{"kind": "CARD_MOVED", "data": {"card_id": 42, "from_zone": 2}}], {"players": [{"id": 0, "monster_zones": []}]})
	_check(director._pending[0].is_empty(), "tribute, bounce, and ordinary movement do not masquerade as destruction")

func _duplicate_and_burst_checks() -> void:
	var card := {"id": 7, "hidden": false, "face_up": true, "name": "The Portrait's Secret", "position": 0}
	var snapshot := {"players": [{"id": 0, "monster_zones": [card]}]}
	director.reset()
	director.ingest(0, [{"kind": "BATTLE_POSITION_CHANGED", "data": {"card_id": 7, "to": 0}},
		{"kind": "FLIP_SUMMON_SUCCEEDED", "data": {"card_id": 7}}], snapshot)
	_check(director._pending[0].size() == 1 and director._pending[0][0]["action"] == "summon", "flip summon coalesces its position event into one reveal")
	director.present(0)
	director.present(0)
	_check(director._queue.size() == 1, "repeated board renders do not replay drained events")
	_drain()
	director.ingest(0, [{"kind": "SPECIAL_SUMMON_SUCCEEDED", "data": {"card_id": 7}}], snapshot)
	_check(director._pending[0].size() == 1 and director._pending[0][0]["action"] == "summon", "special summon success routes through same extensible profile")
	director.skip()
	var entries: Array = []
	for i in range(100): entries.append({"kind": "ATTACK_DECLARED", "data": {"attacker_id": 7}})
	director.ingest(0, entries, snapshot)
	_check(director._pending[0].size() == director.MAX_QUEUED, "event bursts have a bounded cosmetic queue")
	director.present(0)
	director.skip()
	_check(not director.is_busy(), "skip cancels the burst immediately")

func _control_change_checks() -> void:
	director.reset()
	var card := {"id": 7, "hidden": false, "face_up": true, "name": "The Portrait's Secret", "position": 0}
	var target := {"id": 8, "hidden": false, "face_up": true, "name": "Target", "position": 0}
	var snapshot := {"players": [{"id": 0, "monster_zones": [card]}, {"id": 1, "monster_zones": [target]}]}
	var event := {"kind": "ATTACK_DECLARED", "data": {"attacker_id": 7, "target_id": 8}}
	director.ingest(0, [event], snapshot)
	director.present(0)
	director._process(0.1)
	var moved := {"players": [{"id": 0, "monster_zones": []}, {"id": 1, "monster_zones": [target, card]}]}
	director.ingest(0, [], moved)
	_check(director.active.is_empty(), "control change cancels old source-slot animation")
	director.ingest(0, [event], snapshot)
	director.present(0)
	director._process(0.1)
	snapshot["players"][1]["monster_zones"] = [null, target]
	director.ingest(0, [], snapshot)
	_check(director.active.is_empty(), "target relocation cancels a stale target-slot attack")

func _registry_checks() -> void:
	_check(not director.registry.register_profile("Bad", RefCounted.new()), "incomplete profile rejected")
	var profile = preload("res://Scripts/presentation/GenericAnimationProfile.gd").new()
	_check(director.registry.register_profile("Future visible monster", profile), "new card profile can be registered without director changes")
	_check(director.registry.profile_for({"name": "Future visible monster", "hidden": false, "face_up": true}) == profile, "profile dispatch uses visible identity")

func _board_check() -> void:
	var board = load("res://Scenes/ui/DuelBoard.tscn").instantiate()
	root.add_child(board)
	var did_summon := false
	var reached := false
	for i in range(1000):
		await process_frame
		if board.current.is_empty(): continue
		if board.handoff_required: board.reveal_board()
		if int(board._animations.played_counts.get("summon", 0)) > 0:
			reached = true
			break
		for button in board._choices.get_children():
			if button is Button and button.text.begins_with("Normal Summon") and not did_summon:
				did_summon = true
				button.pressed.emit()
				break
			elif button is Button and (button.text.begins_with("Proceed") or button.text.begins_with("Pass")):
				button.pressed.emit()
				break
	_check(reached, "production board plays successful summon through EngineSession projected event feed")
	board.cover_board()
	_check(not board._animations.visible and board._animations.active.is_empty(), "board cover hides animation layer")
	board.start_new_duel()
	_check(board._animations._models == [{}, {}], "board new duel resets animation viewer state")
	board.free()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description)
