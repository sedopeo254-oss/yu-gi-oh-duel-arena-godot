extends SceneTree

## Real main-loop board check, plus selection/cover regressions over delivered-message data.
## Run: bash Tools/run_tests.sh SceneBoardCheck
var screen
var frames := 0
var assertions := 0
var failures: Array[String] = []
var summoned := false
var saw_handoff := false
var restarted := false
var completed := false
var stage := 0
const MOVERS := ["Pass", "Proceed", "Finish the End Phase", "End your turn", "End the Battle Phase", "No"]

func _initialize() -> void:
	screen = load("res://Scenes/ui/DuelBoard.tscn").instantiate()
	root.add_child(screen)

func _process(_delta: float) -> bool:
	if completed: return false
	frames += 1
	if frames > 15000:
		_check(false, "board flow reached its timeout")
		_finish()
		return false
	if screen.current.is_empty(): return false
	if stage == 0:
		_check(screen.handoff_required, "opening hand protected by cover")
		_check(not screen._content.visible, "private content not visible behind cover")
		var pending: Dictionary = screen.current.duplicate(true)
		screen._submit({"offer": 0, "choices": {}})
		_check(screen.current == pending, "covered input ignored")
		screen.reveal_board()
		_check(screen._content.visible and not screen._cover.visible, "reveal shows board")
		_check(screen._board.get_child_count() == 7, "both players, field, phases and hand rendered")
		_check(_count_cards(screen._board) == 10, "ten opening hand cards rendered")
		_selection_checks()
		stage = 1
	if screen.handoff_required:
		saw_handoff = true
		_check(not screen._content.visible, "viewer switch conceals private content")
		screen.reveal_board()
	for player_logs in screen.logs:
		for line in player_logs:
			if "NORMAL_SUMMON_SUCCEEDED" in str(line): summoned = true
	if summoned and saw_handoff and not restarted:
		_check(screen.main_thread_only, "messages handled on the main thread")
		_check(int(screen.session.stats()["rejected"]) == 0, "repeated action click did not enqueue a stale answer")
		screen._inspect({"hidden": true, "id": -123, "name": "must not be displayed"})
		_check(not _all_text(screen._inspector).contains("must not be displayed"), "hidden card inspector ignores identity")
		screen.cover_board()
		_check(not screen._content.visible, "manual cover hides board and inspector")
		screen.start_new_duel()
		_check(screen.current.is_empty() and screen.viewer == -1, "restart clears prompt and viewer")
		_check(screen.logs == [[], []], "restart clears private logs")
		restarted = true
		return false
	if restarted:
		screen.reveal_board()
		var surrender := _button("Surrender")
		if surrender != null:
			surrender.pressed.emit()
			_check(screen._surrender_dialog.visible and not screen.current.is_empty(), "surrender requires confirmation")
			screen._surrender_dialog.hide()
			screen._surrender_dialog.canceled.emit()
			_check(not screen.current.is_empty(), "cancel surrender preserves current prompt")
			surrender.pressed.emit()
			screen._surrender_dialog.confirmed.emit()
			screen._surrender_dialog.hide()
			stage = 2
		return false
	if not summoned:
		var summon := _button("Normal Summon")
		if summon != null:
			summon.pressed.emit()
			summon.pressed.emit()
			_check(screen.current.is_empty(), "submission immediately invalidates the current prompt")
			return false
	if not screen._steps.is_empty():
		var step: Dictionary = screen._steps[screen._step_index]
		for i in range(int(step["min"])): screen._toggle_pick(i)
		screen._confirm_selection()
		return false
	for mover in MOVERS:
		var button := _button(mover)
		if button != null:
			button.pressed.emit()
			return false
	_check(false, "no safe offered continuation")
	_finish()
	return false

func _physics_process(_delta: float) -> bool:
	if not completed and stage == 2 and screen.finished:
		_check(screen.current.is_empty(), "game over removes stale prompt")
		_check(screen.status_line.contains("WINS"), "surrender reports a winner")
		_check(_button("Play again") != null, "game-over rematch button rendered")
		_finish()
	return false

func _selection_checks() -> void:
	var saved: Dictionary = screen.current.duplicate(true)
	var own_hand: Array = screen.view["players"][screen.viewer]["hand"]
	_check(screen._action_label({"label": "Set a Spell/Trap", "card_id": own_hand[0]["id"]}).contains(str(own_hand[0]["name"])), "generic actions identify the visible acting card")
	screen.current = {"mode": "DECISION", "player": screen.viewer, "prompt": "Test selection", "request": {
		"kind": "SELECT_UP_TO", "options": [900, 901, 902], "min_count": 0, "max_count": 2}}
	screen._reset_choice()
	screen._render_actions()
	_check(not _button("Confirm selection").disabled, "zero-minimum selection can be declined")
	screen._toggle_pick(0)
	screen._toggle_pick(1)
	screen._toggle_pick(2)
	_check(screen._picked == [0, 1], "maximum selection count enforced without truncating candidates")
	screen._toggle_pick(0)
	_check(screen._picked == [1], "selected option can be deselected")
	screen.current["request"] = {"kind": "ORDER_TRIGGERS", "options": [{"label": "A"}, {"label": "B"}, {"label": "C"}], "min_count": 3, "max_count": 3}
	screen._reset_choice()
	screen._render_actions()
	_check(_button("Confirm selection").disabled, "incomplete order cannot be submitted")
	for index in [2, 0, 1]: screen._toggle_pick(index)
	_check(screen._picked == [2, 0, 1], "trigger order preserves user permutation")
	_check(not _button("Confirm selection").disabled, "full order can be confirmed")
	_check(screen._decision_labels({"kind": "CHOOSE_POSITION", "options": [0, 1]}) == ["Face Up Attack", "Face Up Defense"], "position decisions label positions, not card IDs")
	_check(screen._decision_labels({"kind": "SELECT_EXACTLY", "options": [-20, -21], "option_labels": ["Known deck card", ""]}) == ["Known deck card", "Offered card"], "provided candidate labels and anonymous fallbacks stay distinct")
	screen.current = saved
	screen._reset_choice()
	var combinations: Array = []
	for i in range(20): combinations.append([100 + i])
	screen._begin_offer({"index": 0, "kind": "TRIBUTE_SUMMON", "tributes_required": 1, "tribute_combinations": combinations})
	_check(screen._steps[0]["values"].size() == 20, "all tribute combinations remain reachable, not capped at twelve")
	screen._reset_choice()
	screen._render_actions()

func _button(prefix: String) -> Button:
	for child in screen._choices.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	return null

func _count_cards(node: Node) -> int:
	var count := 1 if node is ArenaCard else 0
	for child in node.get_children(): count += _count_cards(child)
	return count

func _all_text(node: Node) -> String:
	var result := str(node.text) if node is Label or node is Button else ""
	for child in node.get_children(): result += _all_text(child)
	return result

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition: failures.append(description)

func _finish() -> void:
	completed = true
	print("Board: %d assertions, %d frames, summoned=%s, handoff=%s, restart=%s" % [assertions, frames, summoned, saw_handoff, restarted])
	for failure in failures: print("FAIL: ", failure)
	print("RESULT: ", "PASS" if failures.is_empty() else "FAIL")
	root.remove_child(screen)
	screen.free()
	quit()
