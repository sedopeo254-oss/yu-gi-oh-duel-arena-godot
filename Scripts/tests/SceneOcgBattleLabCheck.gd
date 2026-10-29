extends SceneTree

var screen
var t := TestCase.new("OcgBattleLab")
var started := 0
var stage := 0
var old_pid := -1
var completed := false
const FLOW := ["end_turn", "battle_phase", "attack", "select_monster", "select_monster"]


func _initialize() -> void:
	started = Time.get_ticks_msec()
	screen = load("res://Scenes/dev/OcgBattleLab.tscn").instantiate()
	root.add_child(screen)


func _process(_delta: float) -> bool:
	if completed: return false
	if Time.get_ticks_msec() - started > 15000:
		t.check(false, "UI flow completed before deadline")
		_finish()
		return false
	if screen.finished:
		t.check(false, "lab session unexpectedly finished: %s" % screen.status_line)
		_finish()
		return false
	if screen.current.is_empty(): return false
	if stage == 0:
		t.check(screen.covered and not screen._content.visible, "opening covered for active viewer")
		var pending: Dictionary = screen.current.duplicate(true)
		screen.choose_offer(0)
		t.eq(screen.current, pending, "cover blocks offered actions")
		screen.reveal_board()
		t.check(screen._content.visible and not screen._cover.visible, "reveal shows the field")
		t.check(_all_text(screen._field).contains("Newdoria"), "real Newdoria name appears")
		t.check(_all_text(screen._field).contains("The Portrait's Secret"), "real Portrait name appears")
		t.check(_all_text(screen._field).contains("ATK 1200 / DEF 800"), "real Newdoria stats appear")
		t.eq(screen._field.get_child_count(), 4, "both players and five-zone rows rendered")
		screen.choose_offer(-1)
		t.eq(screen.current, pending, "out-of-range choice ignored")
		# Renderer must not read untrusted identity fields on hidden cards.
		var hidden_view: Dictionary = screen.current.view.duplicate(true)
		hidden_view.players[1].monsters[0] = {"slot": 0, "position": 8, "known": false, "code": 32541773, "attack": 123456, "defense": 123456}
		screen._render_view(hidden_view)
		t.check(not _all_text(screen._field).contains("The Portrait's Secret") and not _all_text(screen._field).contains("123456"), "hidden-card renderer ignores identity fields")
		screen._render()
	if stage < FLOW.size():
		if screen.covered:
			t.check(not screen._content.visible, "handoff hides previous player's field")
			screen.reveal_board()
		var kind: String = FLOW[stage]
		var index := _offer(kind)
		if not t.check(index >= 0, "UI receives %s offer" % kind):
			_finish()
			return false
		var button: Button = screen._choices.get_child(index)
		button.pressed.emit()
		button.pressed.emit()
		t.check(screen.current.is_empty(), "click consumes prompt immediately and double-click cannot resubmit")
		stage += 1
		return false
	if stage == FLOW.size():
		t.eq(int(screen.current.view.players[0].graveyard_count), 1, "UI receives battle-destroyed Newdoria GY")
		t.eq(int(screen.current.view.players[1].graveyard_count), 1, "UI receives effect-destroyed Portrait GY")
		t.check(not _all_text(screen._field).contains("Newdoria"), "resolved field no longer renders Newdoria")
		old_pid = screen.session.process_id()
		screen.cover_board()
		t.check(not screen._content.visible, "manual cover hides field and choices")
		screen.start_new_duel()
		t.check(not OS.is_process_running(old_pid), "restart reaps old native child")
		t.check(screen.current.is_empty() and screen.viewer == -1, "restart clears private state")
		stage += 1
		return false
	old_pid = screen.session.process_id()
	screen.close_session()
	t.check(screen.finished and screen.current.is_empty() and screen.covered, "close clears controls and covers")
	t.check(not OS.is_process_running(old_pid), "close reaps native process")
	t.check(screen._field.get_child_count() == 0 and screen._choices.get_child_count() == 0, "close removes rendered state and stale buttons")
	_finish()
	return false


func _offer(kind: String) -> int:
	for i in screen.current.offers.size():
		if screen.current.offers[i].kind == kind: return i
	return -1


func _all_text(node: Node) -> String:
	var result := ""
	if node is Label: result += node.text + "\n"
	for child in node.get_children(): result += _all_text(child)
	return result


func _finish() -> void:
	completed = true
	if screen.session != null: screen.session.stop()
	screen.queue_free()
	print(t.report())
	print("TOTAL: %d passed, %d failed" % [t.passed, t.failed])
	print("RESULT: %s" % ("PASS" if t.failed == 0 else "FAIL"))
	quit(0 if t.failed == 0 else 1)
