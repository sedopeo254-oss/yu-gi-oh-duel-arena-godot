extends SceneTree


func _initialize() -> void:
	var t := TestCase.new("OcgReferenceSession")
	_test_choices(t)
	_test_lifecycle(t)
	_test_transport_boundary(t)
	_test_deck_out(t)
	print(t.report())
	print("TOTAL: %d passed, %d failed" % [t.passed, t.failed])
	print("RESULT: %s" % ("PASS" if t.failed == 0 else "FAIL"))
	quit(0 if t.failed == 0 else 1)


func _wait(session: OcgReferenceSession, viewer: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var messages := session.poll(viewer)
		if not messages.is_empty():
			return messages[0]
		OS.delay_usec(500)
	return {"type": "timeout", "reason": session.last_error()}


func _alive(pid: int) -> bool:
	# Godot's child tracker intentionally forgets a reaped PID; asking it again
	# logs ECHILD. An external signal-zero probe verifies OS process absence.
	if pid < 1:
		return false
	return OS.execute("/bin/kill", PackedStringArray(["-0", str(pid)]), [], true) == 0


func _test_choices(t: TestCase) -> void:
	t.start("real choices, private channels and stale-answer validation")
	var session := OcgReferenceSession.new()
	t.check(not session.start_fixture(-1), "invalid seed is refused")
	if not t.check(session.start_fixture(42), "native session starts"):
		return
	t.check(not session.start_fixture(42), "cannot start the same session twice")
	var prompt := _wait(session, 0)
	if not t.eq(prompt.get("type"), "prompt", "opening native prompt: %s" % prompt):
		session.stop()
		return
	t.eq(session.poll(1).size(), 0, "other player's channel receives no opening prompt")
	t.eq(prompt.prompt_id, 1, "first player's prompt sequence starts at one")
	t.eq(int(prompt.view.players[0].hand_count), 5, "native opening hand count")
	t.check(not session.submit(0, 1, {"offer": 0, "seed": 42}), "unrecognized answer fields rejected locally")
	t.check(session.submit(1, 1, {"offer": 0}), "wrong-player request reaches native authority")
	var rejected := _wait(session, 1)
	t.eq(rejected.get("type"), "rejected", "native rejects wrong player")
	t.eq(session.poll(0).size(), 0, "wrong player's rejection does not advance active channel")
	t.check(session.submit(0, 1, {"offer": 999}), "invalid choice reaches native authority")
	t.eq(_wait(session, 0).get("type"), "rejected", "native rejects index outside offered choices")
	# Mutating delivered data cannot alter either native legality or the next view.
	prompt.offers.clear()
	t.check(session.submit(0, 1, {"offer": 0}), "legal original summon index remains valid")
	t.check(not session.submit(0, 1, {"offer": 0}), "duplicate concurrent submission not queued")
	var zone := _wait(session, 0)
	if not t.eq(zone.get("type"), "prompt", "core requests a monster zone: %s" % zone):
		session.stop()
		return
	t.eq(zone.mode, "DECISION", "zone choice is a mid-action decision")
	t.eq(zone.offers[0].kind, "choose_zone", "legal zone choices decoded from the core")
	t.check(session.submit(0, 1, {"offer": 0}), "stale response reaches native authority")
	t.eq(_wait(session, 0).get("type"), "rejected", "native rejects stale prompt id")
	t.check(session.submit(0, zone.prompt_id, {"offer": 0}), "current zone response accepted for processing")
	var after := _wait(session, 0)
	if t.eq(after.get("type"), "prompt", "summon completes: %s" % after):
		t.eq(int(after.view.players[0].hand_count), 4, "one card left hand")
		t.eq(int(after.view.players[0].monster_count), 1, "one monster on native field")
		var normal_count := 0
		var end_index := -1
		for i in after.offers.size():
			if after.offers[i].kind == "normal_summon": normal_count += 1
			if after.offers[i].kind == "end_turn": end_index = i
		t.eq(normal_count, 0, "native core does not offer a second Normal Summon")
		t.check(session.submit(0, after.prompt_id, {"offer": end_index}), "end turn submitted")
		var next := _wait(session, 1)
		if t.eq(next.get("type"), "prompt", "second player's prompt: %s" % next):
			t.eq(next.prompt_id, 1, "second player's sequence independent of opponent decisions")
			t.eq(int(next.view.players[1].hand_count), 6, "second player draws through native core")
			t.eq(session.poll(0).size(), 0, "opponent turn does not publish to first player's channel")
	var pid := session.process_id()
	session.stop()
	t.check(not _alive(pid), "explicit stop terminates child")
	t.eq(_wait(session, 0).get("type"), "stopped", "stopped event published")
	session.stop()
	t.eq(session.poll(0).size(), 0, "repeated stop does not duplicate events")
	t.check(not session.submit(0, 1, {"offer": 0}), "submission after stop rejected")


func _test_lifecycle(t: TestCase) -> void:
	t.start("child crash, owner destruction and independent sessions")
	var a := OcgReferenceSession.new()
	var b := OcgReferenceSession.new()
	if not t.check(a.start_fixture(7) and b.start_fixture(8), "two independent core processes start"):
		a.stop()
		b.stop()
		return
	var a_prompt := _wait(a, 0)
	var b_prompt := _wait(b, 0)
	t.eq(a_prompt.get("type"), "prompt", "first independent opening")
	t.eq(b_prompt.get("type"), "prompt", "second independent opening")
	var a_pid := a.process_id()
	t.check(a_pid != b.process_id(), "separate processes isolate global callbacks")
	OS.execute("/bin/kill", PackedStringArray(["-KILL", str(a_pid)]), [], true)
	t.eq(_wait(a, 0).get("type"), "error", "crashed child becomes an explicit error")
	t.eq(a.poll(1)[0].type, "error", "both channels see the transport failure")
	t.check(not a.is_running(), "crashed session stops accepting actions")
	t.check(b.is_running(), "other native duel survives isolated crash")
	var b_pid := b.process_id()
	b = null
	var deadline := Time.get_ticks_msec() + 1000
	while _alive(b_pid) and Time.get_ticks_msec() < deadline:
		OS.delay_usec(1000)
	t.check(not _alive(b_pid), "dropping last session reference terminates child")
	a.stop()


func _test_deck_out(t: TestCase) -> void:
	t.start("full reference session to actual native deck-out")
	var session := OcgReferenceSession.new()
	if not t.check(session.start_fixture(0), "deck-out session starts"):
		return
	var last_ids := [0, 0]
	var ended := [false, false]
	var actions := 0
	var discards := 0
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not (ended[0] and ended[1]):
		for viewer in [0, 1]:
			for message in session.poll(viewer):
				if message.type == "prompt":
					t.eq(message.player, viewer, "prompt delivered only to addressed player")
					t.eq(message.prompt_id, last_ids[viewer] + 1, "per-player prompt sequence has no gaps")
					last_ids[viewer] = message.prompt_id
					t.check(OcgReferenceSession._valid_view(message.view), "snapshot is strictly count-only")
					var index := -1
					for i in message.offers.size():
						if message.offers[i].kind == "end_turn" or message.offers[i].kind == "discard":
							index = i
							break
					if index >= 0 and message.offers[index].kind == "discard": discards += 1
					t.check(index >= 0 and session.submit(viewer, message.prompt_id, {"offer": index}), "supported choice queued")
					actions += 1
				elif message.type == "over":
					ended[viewer] = true
					t.eq(int(message.winner), 0, "player zero wins when player one must draw from empty deck")
					t.eq(int(message.reason_code), 2, "native deck-out reason")
				elif message.type == "error":
					t.check(false, "unexpected native failure: %s" % message)
					ended = [true, true]
		OS.delay_usec(500)
	t.check(ended[0] and ended[1], "both viewers receive the terminal result")
	t.eq(actions, 139, "complete native turn/discard trace")
	t.eq(discards, 68, "hand-limit discards were answered through native prompts")
	t.check(not session.is_running(), "terminal result prevents more submissions")
	var pid := session.process_id()
	session.stop()
	t.check(not _alive(pid), "completed session releases the child process")


func _test_transport_boundary(t: TestCase) -> void:
	t.start("fail closed on hidden fields and incomplete/unclean terminal transport")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OcgCoreDiagnostic.LOCK_PATH))
	for mode in ["hidden_top", "hidden_offer", "invalid_mode", "crash_after_over", "hang_after_over", "one_over", "mismatched_view", "mismatched_winner", "duplicate_over", "prompt_after_over"]:
		var session := OcgReferenceSession.new()
		# Inject a controlled broken transport into a test instance, not a public
		# executable-path override in the production-facing session API.
		var child := OS.execute_with_pipe("python3", PackedStringArray([
			ProjectSettings.globalize_path("res://Tools/ocg/fake_session_worker.py"), mode]), false)
		if not t.check(not child.is_empty(), "test worker starts: %s" % mode):
			continue
		session._pid = int(child.pid)
		session._child_live = true
		session._stdio = child.stdio
		session._stderr = child.stderr
		session._revision = manifest.core.revision
		session._started = true
		session._pending = true
		session._deadline = Time.get_ticks_msec() + 3000
		var pid := session.process_id()
		var event := _wait(session, 0)
		t.eq(event.get("type"), "error", "bad worker never publishes success or private fields: %s" % mode)
		t.check(not event.has("opponent_hand_ids"), "unapproved top-level field stays private")
		t.check(not session.is_running(), "invalid worker terminates: %s" % mode)
		t.check(not _alive(pid), "failed/hung child reaped: %s" % mode)
		session.stop()
