extends SceneTree

class MissingCoreBoard:
	extends "res://Scripts/ui/DuelBoard.gd"
	func _native_core_available() -> bool:
		return false

var t := TestCase.new("ArenaCoreNavigation")
var screen


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	screen = load("res://Scenes/ui/DuelBoard.tscn").instantiate()
	root.add_child(screen)
	await _wait_board()
	t.check(not screen.current.is_empty(), "original arena session starts")
	screen._sound.persist_preferences = false
	screen._sound.set_enabled(true)
	screen._sound.set_volume(0.23)
	screen.reveal_board()
	var original: Dictionary = screen.current.duplicate(true)
	var original_session: EngineSession = screen.session
	var original_seed: int = screen.seed_value
	screen._sound.play_cue("attack")
	t.check(screen._sound._voice.playing, "existing sound available before opening lab dialog")
	screen._request_native_lab()
	t.check(screen._native_dialog.visible and screen._native_lab == null, "opening lab requires confirmation before creating child")
	t.check(screen.handoff_required and not screen._content.visible, "modal request conceals private board")
	t.check(not screen._sound._voice.playing, "modal request cancels playing arena sound")
	t.check(screen.current == original and original_session.is_running(), "request alone does not end duel")
	screen._native_dialog.hide()
	screen._native_dialog.canceled.emit()
	t.check(screen.current == original and screen.session == original_session, "cancel preserves exact arena prompt/session")
	for dimensions in [Vector2i(1600, 900), Vector2i(390, 844), Vector2i(320, 640)]:
		root.size = dimensions
		screen._sync_window_layout()
		await process_frame
		await process_frame
		var entry := _find_button(screen._cover, "Experimental core lab")
		t.check(entry != null and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(entry.get_global_rect()), "cover entry fits %s" % dimensions)
		screen._request_native_lab()
		await process_frame
		t.check(screen._native_dialog.visible and screen._native_dialog.size.x <= dimensions.x and screen._native_dialog.size.y <= dimensions.y, "confirmation fits %s" % dimensions)
		screen._native_dialog.hide()
	root.size = Vector2i(1600, 900)
	screen._sync_window_layout()
	screen._request_native_lab()
	screen._native_dialog.confirmed.emit()
	await _wait_lab()
	t.check(not original_session.is_running() and screen.session == null, "confirmed entry joins old arena worker")
	t.check(screen.current.is_empty() and screen.view.is_empty() and screen.logs == [[], []], "entry clears old private snapshots/logs")
	t.check(is_instance_valid(screen._native_lab), "native lab is hosted above covered arena")
	var lab = screen._native_lab
	var native_pid: int = lab.session.process_id()
	t.check(native_pid > 0 and OS.is_process_running(native_pid), "real native child runs only after confirmation")
	screen._request_native_lab()
	t.check(screen._native_lab == lab and lab.session.process_id() == native_pid, "repeated entry cannot create duplicate lab")
	for dimensions in [Vector2i(390, 844), Vector2i(320, 640), Vector2i(1600, 900)]:
		root.size = dimensions
		screen._sync_window_layout()
		lab._sync_layout()
		lab.reveal_board()
		await process_frame
		await process_frame
		t.check(lab._content.get_combined_minimum_size().x <= dimensions.x - 24, "lab content fits viewport width %s" % dimensions)
		t.eq(lab._choices.columns, 1 if dimensions.x < 700 else 2, "lab actions reflow without shrinking touch targets")
	for kind in ["end_turn", "battle_phase", "attack", "select_monster", "select_monster"]:
		lab.reveal_board()
		var index := _offer(lab.current, kind)
		if not t.check(index >= 0, "integrated lab receives %s" % kind): break
		(lab._choices.get_child(index) as Button).pressed.emit()
		await _wait_lab()
	if not lab.current.is_empty():
		t.eq(int(lab.current.view.players[0].graveyard_count), 1, "integrated lab executes Newdoria battle destruction")
		t.eq(int(lab.current.view.players[1].graveyard_count), 1, "integrated lab executes target effect destruction")
	lab.return_to_arena()
	lab.return_to_arena()
	await process_frame
	await _wait_board()
	t.check(not OS.is_process_running(native_pid), "return closes native child before new arena")
	t.check(screen._native_lab == null and screen._native_layer == null, "return removes native overlay")
	t.check(screen.session != original_session and screen.session.is_running(), "return starts a fresh original-engine session")
	t.eq(screen.seed_value, original_seed + 1, "double return creates only one fresh shuffle")
	t.check(screen.handoff_required and not screen.current.is_empty(), "fresh arena returns covered with legal prompt")
	t.check(is_equal_approx(screen._sound.volume, 0.23) and screen._sound.enabled, "arena sound preferences survive navigation")
	screen._sound.play_cue("summon")
	t.check(screen._sound._voice.playing, "existing original audio still works after return")
	screen._request_native_lab()
	screen._native_dialog.confirmed.emit()
	await _wait_lab()
	native_pid = screen._native_lab.session.process_id()
	screen.free()
	t.check(not OS.is_process_running(native_pid), "closing host while lab open reaps native child")
	screen = MissingCoreBoard.new()
	root.add_child(screen)
	await _wait_board()
	var still_running: EngineSession = screen.session
	var unchanged: Dictionary = screen.current.duplicate(true)
	screen._request_native_lab()
	t.check(screen._native_unavailable.visible and not screen._native_dialog.visible, "missing build reports prerequisite rather than offering destructive launch")
	t.check(screen._native_lab == null and screen.session == still_running and still_running.is_running(), "missing binary leaves arena worker alive")
	t.eq(screen.current, unchanged, "missing binary preserves prompt")
	screen._native_unavailable.hide()
	screen.reveal_board()
	t.check(not screen.handoff_required, "unavailable dialog dismissal can resume original duel")
	screen.free()
	await create_timer(1.1).timeout
	await process_frame
	print(t.report())
	print("TOTAL: %d passed, %d failed" % [t.passed, t.failed])
	print("RESULT: %s" % ("PASS" if t.failed == 0 else "FAIL"))
	quit(0 if t.failed == 0 else 1)


func _wait_board() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if not screen.current.is_empty(): return
		await process_frame


func _wait_lab() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(screen._native_lab) and not screen._native_lab.current.is_empty(): return
		await process_frame
	t.check(false, "native lab prompt timed out")


func _offer(prompt: Dictionary, kind: String) -> int:
	for i in prompt.get("offers", []).size():
		if prompt.offers[i].kind == kind: return i
	return -1


func _find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption: return node
	for child in node.get_children():
		var result := _find_button(child, caption)
		if result != null: return result
	return null
