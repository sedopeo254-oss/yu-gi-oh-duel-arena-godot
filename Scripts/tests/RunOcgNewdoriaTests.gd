extends SceneTree


func _initialize() -> void:
	var t := TestCase.new("OcgNewdoriaSession")
	var session := OcgReferenceSession.new()
	t.start("official two-card metadata and real Lua battle trigger")
	if not t.check(session.start_newdoria_fixture(42), "real-card fixture starts"):
		print(t.report())
		print("RESULT: FAIL")
		quit(1)
		return
	var prompt := _wait(session, 0)
	if not t.eq(prompt.get("type"), "prompt", "opening: %s" % prompt):
		session.stop()
		print(t.report())
		print("RESULT: FAIL")
		quit(1)
		return
	t.eq(int(prompt.view.players[0].monsters[0].code), 4335645, "leading zero passcode maps to Newdoria core ID")
	t.eq(int(prompt.view.players[0].monsters[0].defense), 800, "Newdoria's official DEF loaded from data")
	t.eq(int(prompt.view.players[1].monsters[0].code), 32541773, "Portrait's official identity loaded")
	t.eq(int(prompt.view.players[1].monsters[0].attack), 1200, "Portrait's official ATK loaded")
	t.check(OcgReferenceSession._valid_view(prompt.view, true, 0), "real-card view is viewer-filtered")
	t.start("rich-view privacy and schema rejection")
	var private_view: Dictionary = prompt.view.duplicate(true)
	private_view.players[0].monsters[0].position = 8
	t.check(OcgReferenceSession._valid_view(private_view, true, 0), "own face-down identity remains visible to owner")
	var public_view: Dictionary = private_view.duplicate(true)
	public_view.viewer = 1
	public_view.players[0].monsters[0] = {"slot": 0, "position": 8, "known": false}
	t.check(OcgReferenceSession._valid_view(public_view, true, 1), "opponent face-down is count/location only")
	t.check(OcgReferenceSession._matching_terminal_views(private_view, public_view, true), "terminal projections may differ only in concealed identities")
	public_view.players[0].monsters[0]["code"] = 4335645
	t.check(not OcgReferenceSession._valid_view(public_view, true, 1), "hidden identity field rejected at transport boundary")
	public_view.players[0].monsters[0].erase("code")
	public_view.players[0].life_points = 7999
	t.check(not OcgReferenceSession._matching_terminal_views(private_view, public_view, true), "terminal LP disagreement rejected")
	private_view.players[0].monsters[0].known = false
	t.check(not OcgReferenceSession._valid_view(private_view, true, 0), "owner projection cannot claim wrong visibility")
	private_view = prompt.view.duplicate(true)
	private_view.players[0].monster_count = 2
	t.check(not OcgReferenceSession._valid_view(private_view, true, 0), "zone occupancy must match count")
	private_view = prompt.view.duplicate(true)
	private_view.players[0].graveyard_count = 41
	t.check(OcgReferenceSession._valid_view(private_view, true, 0), "arranged field card plus 40-card deck fits graveyard bound")
	private_view.players[0].graveyard_count = 42
	t.check(not OcgReferenceSession._valid_view(private_view, true, 0), "graveyard cannot exceed admitted card count")
	private_view = prompt.view.duplicate(true)
	private_view.players[0].monsters[0].attack = 1200.5
	t.check(not OcgReferenceSession._valid_view(private_view, true, 0), "fractional native stats rejected")
	prompt = _choose(t, session, prompt, "end_turn", 1)
	prompt = _choose(t, session, prompt, "battle_phase", 1)
	prompt = _choose(t, session, prompt, "attack", 1)
	prompt = _choose(t, session, prompt, "select_monster", 0)
	if prompt.get("type") == "prompt":
		t.eq(prompt.player, 0, "Newdoria's controller owns the trigger target choice")
		t.eq(int(prompt.view.players[0].graveyard_count), 1, "Newdoria reached GY before effect targeting")
		t.eq(int(prompt.view.players[0].monster_count), 0, "battle destruction removed Newdoria")
		t.eq(prompt.offers.size(), 1, "mandatory trigger has a target and no decline offer")
	prompt = _choose(t, session, prompt, "select_monster", 1)
	if prompt.get("type") == "prompt":
		for player in [0, 1]:
			t.eq(int(prompt.view.players[player].graveyard_count), 1, "battle/effect each moved one card to GY")
			t.eq(int(prompt.view.players[player].monster_count), 0, "both real fixture cards left the field")
			t.eq(int(prompt.view.players[player].life_points), 8000, "attack into lower DEF dealt no LP damage")
	t.start("continue same native session to an actual LP victory")
	# Return to Main Phase 2 and finish turn 2; player 1 then passes while player 0
	# summons/attacks with the admitted Normal Monster fixtures. No state editing.
	if prompt.get("type") == "prompt":
		prompt = _choose(t, session, prompt, "end_turn", 0)
	var ended := [false, false]
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and not (ended[0] and ended[1]):
		if prompt.get("type") == "prompt":
			var priorities: Array = ["normal_summon", "choose_zone", "battle_phase", "attack", "select_monster", "chain_effect", "discard", "end_turn", "main_two", "pass_chain"] if prompt.player == 0 else ["discard", "end_turn", "main_two"]
			var index := -1
			for wanted in priorities:
				for i in prompt.offers.size():
					if prompt.offers[i].kind == wanted:
						index = i
						break
				if index >= 0: break
			t.check(index >= 0 and session.submit(prompt.player, prompt.prompt_id, {"offer": index}), "LP-duel core choice queued")
			prompt = {}
		for viewer in [0, 1]:
			for message in session.poll(viewer):
				if message.type == "prompt": prompt = message
				elif message.type == "over":
					ended[viewer] = true
					t.eq(int(message.winner), 0, "attacking player wins the continuing duel")
					t.eq(int(message.reason_code), 1, "core reports an LP victory, not fabricated completion")
					t.eq(int(message.view.players[1].life_points), 0, "defeated player displays zero LP")
				elif message.type == "error":
					t.check(false, "native failure: %s" % message)
					ended = [true, true]
		OS.delay_usec(500)
	t.check(ended[0] and ended[1], "both players receive the completed duel")
	t.check(not session.is_running(), "native duel exits cleanly before completion publication")
	session.stop()
	print(t.report())
	print("TOTAL: %d passed, %d failed" % [t.passed, t.failed])
	print("RESULT: %s" % ("PASS" if t.failed == 0 else "FAIL"))
	quit(0 if t.failed == 0 else 1)


func _wait(session: OcgReferenceSession, viewer: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		var messages := session.poll(viewer)
		if not messages.is_empty(): return messages[0]
		OS.delay_usec(500)
	return {"type": "timeout", "reason": session.last_error()}


func _choose(t: TestCase, session: OcgReferenceSession, prompt: Dictionary, kind: String, next_player: int) -> Dictionary:
	if prompt.get("type") != "prompt": return prompt
	var index := -1
	for i in prompt.offers.size():
		if prompt.offers[i].kind == kind:
			index = i
			break
	if not t.check(index >= 0, "core offered %s" % kind): return {}
	t.check(session.submit(prompt.player, prompt.prompt_id, {"offer": index}), "submit %s" % kind)
	var result := _wait(session, next_player)
	t.eq(result.get("type"), "prompt", "next native prompt after %s: %s" % [kind, result])
	return result
