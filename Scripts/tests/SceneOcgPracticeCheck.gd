extends SceneTree

var t := TestCase.new("OcgPracticeUI")
var screen

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600, 900)
	screen = load("res://Scenes/dev/OcgBattleLab.tscn").instantiate()
	root.add_child(screen)
	await _wait()
	var prior_pid: int = screen.session.process_id()
	t.eq(screen._mode_selection.item_count, 3, "scenario plus two practice profiles offered")
	screen._mode_selection.select(1)
	t.eq(screen.session.process_id(), prior_pid, "selecting a different mode alone does not abandon current duel")
	screen.start_new_duel()
	await _wait()
	t.check(not OS.is_process_running(prior_pid), "starting selected mode reaps previous native scenario")
	t.eq(screen._active_mode, 1, "mixed profile becomes active")
	t.check(screen.covered and not screen._hand.is_visible_in_tree(), "private hand covered on initial handoff")
	screen.reveal_board()
	t.eq(screen._hand.get_child_count(), 6, "owner's five real cards and hand header are rendered")
	t.check(screen.current.view.players[0].hand.all(func(card): return _text(screen._hand).contains(str(screen._names[int(card.code)]))), "imported official names are rendered from own snapshot")
	t.check(_text(screen._guide).contains("exceed three copies"), "non-tournament practice limitation visible")
	var planted: Dictionary = screen.current.view.duplicate(true)
	planted.players[1].hand = [{"slot": 0, "code": 43096270, "attack": 98765, "defense": 98765}]
	screen._render_view(planted)
	t.check(not _text(screen._hand).contains("98765"), "renderer never reads opponent hand array")
	screen._render()
	await _click("set_monster")
	await _click("choose_zone")
	t.eq(int(screen.current.view.players[0].monsters[0].position), 8, "UI sets a real monster face-down")
	t.eq(screen._hand.get_child_count(), 5, "own hand updates after setting")
	await _click("end_turn")
	t.check(screen.covered and not screen._content.visible, "viewer switch hides old private hand")
	t.eq(screen.current.view.players[0].hand, [], "new viewer receives no old-player hand identities")
	t.check(not screen.current.view.players[0].monsters[0].known, "set monster stays hidden to opponent")
	screen.reveal_board()
	t.check(_text(screen._hand).contains("PLAYER 2 ONLY"), "hand panel changes to correct owner")
	await _click("end_turn")
	await _click("reposition")
	t.eq(int(screen.current.view.players[0].monsters[0].position), 1, "UI Flip Summon uses native rule choice")
	prior_pid = screen.session.process_id()
	screen._mode_selection.select(2)
	screen.start_new_duel()
	await _wait()
	t.check(not OS.is_process_running(prior_pid), "switching deck profiles closes old child")
	for card in screen.current.view.players[0].hand:
		t.check(int(card.code) in [43096270, 11091375, 21615956], "Dragon-only profile excludes other races")
	for dimensions in [Vector2i(390, 844), Vector2i(320, 640)]:
		root.size = dimensions
		screen._sync_layout()
		screen.reveal_board()
		await process_frame
		await process_frame
		t.check(screen._content.get_combined_minimum_size().x <= dimensions.x - 24, "practice field/hand fit narrow width %s" % dimensions)
		t.check(screen._mode_selection.size.x <= dimensions.x - 24, "mode selector fits narrow width %s" % dimensions)
	prior_pid = screen.session.process_id()
	screen.close_session()
	t.check(not OS.is_process_running(prior_pid) and screen._hand.get_child_count() == 0, "close reaps child and clears private hand")
	screen.free()
	print(t.report())
	print("TOTAL: %d passed, %d failed" % [t.passed, t.failed])
	print("RESULT: %s" % ("PASS" if t.failed == 0 else "FAIL"))
	quit(0 if t.failed == 0 else 1)

func _click(kind: String) -> void:
	screen.reveal_board()
	var index := -1
	for i in screen.current.offers.size():
		if screen.current.offers[i].kind == kind: index = i; break
	if not t.check(index >= 0, "UI offers %s" % kind): return
	(screen._choices.get_child(index) as Button).pressed.emit()
	await _wait()

func _wait() -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if not screen.current.is_empty(): return
		await process_frame
	t.check(false, "native practice UI response timed out: %s" % screen.status_line)

func _text(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += _text(child)
	return result
