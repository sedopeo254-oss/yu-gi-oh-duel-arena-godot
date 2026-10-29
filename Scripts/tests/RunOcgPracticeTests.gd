extends SceneTree

var t := TestCase.new("OcgPracticePool")

func _initialize() -> void:
	var invalid := OcgReferenceSession.new()
	t.check(not invalid.start_practice_deck("../../effect.lua"), "profile cannot be a script/path")
	t.eq(invalid.process_id(), -1, "invalid profile launches no child")
	var session := OcgReferenceSession.new()
	t.check(session.start_practice_deck("mixed", 42), "mixed real-card mode starts")
	var prompt := _wait(session)
	if not t.check(prompt.get("type") == "prompt", "native practice prompt: %s" % prompt):
		session.stop()
		_finish()
		return
	t.eq(prompt.view.players[0].hand.size(), 5, "owner receives five actual hand identities")
	t.eq(prompt.view.players[1].hand, [], "opponent hand identities absent")
	t.eq(int(prompt.view.players[0].monster_count), 0, "no arranged field in real-card practice mode")
	t.check(OcgReferenceSession._valid_view(prompt.view, true, 0, true), "practice snapshot schema accepted")
	var injected: Dictionary = prompt.view.duplicate(true)
	injected.players[1].hand = [injected.players[0].hand[0]]
	t.check(not OcgReferenceSession._valid_view(injected, true, 0, true), "opponent hand injection rejected")
	injected = prompt.view.duplicate(true)
	injected.players[0].hand[0].extra_private_key = 1
	t.check(not OcgReferenceSession._valid_view(injected, true, 0, true), "unknown own-hand fields rejected")
	injected = prompt.view.duplicate(true)
	injected.players[0].hand[0].code = 83764719
	t.check(not OcgReferenceSession._valid_view(injected, true, 0, true), "unapproved hand code rejected")
	var selected_code := int(prompt.view.players[0].hand[0].code)
	prompt = _choose(session, prompt, "set_monster")
	prompt = _choose(session, prompt, "choose_zone")
	t.eq(int(prompt.view.players[0].monsters[0].position), 8, "set resolves face-down Defense")
	t.eq(int(prompt.view.players[0].monsters[0].code), selected_code, "owner still knows own set monster")
	prompt = _choose(session, prompt, "end_turn")
	t.eq(prompt.view.players[0].monsters[0], {"slot": 0.0, "position": 8.0, "known": false}, "opponent receives only opaque field position")
	t.eq(prompt.view.players[0].hand, [], "old owner's hand not copied on player handoff")
	prompt = _choose(session, prompt, "end_turn")
	prompt = _choose(session, prompt, "reposition")
	t.eq(int(prompt.view.players[0].monsters[0].position), 1, "Flip Summon resolves into face-up Attack")
	# Continue this same private-hand session to test terminal projection comparison.
	var ended := [false, false]
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and not (ended[0] and ended[1]):
		if prompt.get("type") == "prompt":
			var priorities: Array = ["normal_summon", "choose_zone", "battle_phase", "attack", "select_monster", "discard", "end_turn", "main_two"] if prompt.player == 0 else ["discard", "end_turn", "main_two"]
			var index := -1
			for kind in priorities:
				index = _offer(prompt, kind)
				if index >= 0: break
			t.check(index >= 0 and session.submit(prompt.player, prompt.prompt_id, {"offer": index}), "practice native choice accepted for processing")
			prompt = {}
		for viewer in [0, 1]:
			for message in session.poll(viewer):
				if message.type == "prompt": prompt = message
				elif message.type == "over":
					ended[viewer] = true
					t.eq(int(message.winner), 0, "native practice LP winner")
					t.eq(int(message.reason_code), 1, "actual LP victory")
					t.eq(message.view.players[1 - viewer].hand, [], "terminal report still hides opponent hand")
				elif message.type == "error":
					t.check(false, "native error: %s" % message)
					ended = [true, true]
		OS.delay_usec(500)
	t.check(ended[0] and ended[1] and not session.is_running(), "two private terminal projections accepted only after clean exit")
	session.stop()
	var mismatch := OcgReferenceSession.new()
	t.check(mismatch.start_practice_deck("dragons", 42), "second approved profile launches")
	mismatch._pool_digest = "0".repeat(64)
	var failure := _wait(mismatch)
	t.eq(failure.get("type"), "error", "stale or changed compiled metadata hash fails closed")
	t.check(not mismatch.is_running() and mismatch.process_id() == -1, "metadata mismatch reaps child")
	_finish()

func _wait(session: OcgReferenceSession) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		for viewer in [0, 1]:
			var messages := session.poll(viewer)
			if not messages.is_empty(): return messages[0]
		OS.delay_usec(500)
	return {"type": "timeout", "reason": session.last_error()}

func _choose(session: OcgReferenceSession, prompt: Dictionary, kind: String) -> Dictionary:
	var index := _offer(prompt, kind)
	if not t.check(index >= 0, "offered %s" % kind): return {}
	t.check(session.submit(prompt.player, prompt.prompt_id, {"offer": index}), "submit %s" % kind)
	var result := _wait(session)
	t.eq(result.get("type"), "prompt", "prompt after %s" % kind)
	return result

func _offer(prompt: Dictionary, kind: String) -> int:
	for i in prompt.get("offers", []).size():
		if prompt.offers[i].kind == kind: return i
	return -1

func _finish() -> void:
	print(t.report())
	print("TOTAL: %d passed, %d failed" % [t.passed, t.failed])
	print("RESULT: %s" % ("PASS" if t.failed == 0 else "FAIL"))
	quit(0 if t.failed == 0 else 1)
