extends SceneTree

## A real, unarranged local duel through the board's own interaction handlers.
## This conservative TEST policy is not a CPU opponent feature: it passes optional effects,
## summons/tributes, attacks and advances phases until a natural game result occurs.
## Run: bash Tools/run_tests.sh SceneBoardDuelCheck
var screen
var frames := 0
var actions := 0
var done := false
func _initialize():
	screen = load("res://Scenes/ui/DuelBoard.tscn").instantiate()
	root.add_child(screen)
func _process(_delta):
	if done: return false
	frames += 1
	if screen.finished:
		finish("PASS")
		return false
	if frames > 40000:
		finish("TIMEOUT")
		return false
	if screen.current.is_empty(): return false
	if screen.handoff_required: screen.reveal_board()
	if not screen._steps.is_empty():
		var step = screen._steps[screen._step_index]
		for i in range(int(step["min"])): screen._toggle_pick(i)
		screen._confirm_selection()
		return false
	if str(screen.current["mode"]) == "DECISION":
		for button in screen._choices.get_children():
			if button is Button and button.text == "No":
				button.pressed.emit()
				return false
		finish("UNHANDLED_DECISION")
		return false
	var preferred = ["PASS"] if str(screen.current["mode"]) == "RESPONSE" else ["NORMAL_SUMMON", "TRIBUTE_SUMMON", "FLIP_SUMMON", "DECLARE_ATTACK", "ENTER_BATTLE_PHASE", "SET_SPELL_TRAP", "END_BATTLE_PHASE", "GO_TO_MAIN_2", "END_PHASE", "END_TURN", "PASS"]
	for kind in preferred:
		for offer in screen.current.get("offers", []):
			if str(offer["kind"]) == kind:
				actions += 1
				screen._begin_offer(offer)
				return false
	finish("UNHANDLED_ACTION")
	return false
func finish(result):
	done = true
	var stats: Dictionary = screen.session.stats()
	if int(stats["rejected"]) != 0 or int(stats["refused_by_engine"]) != 0 or not screen.main_thread_only:
		result = "INVALID_INTERACTION"
	if screen.status_line.contains("SURRENDER"):
		result = "NOT_A_NATURAL_RESULT"
	print("UI NATURAL DUEL: ", result, " | frames=", frames, " actions=", actions, " turn=", screen.view.get("turn"), " status=", screen.status_line, " stats=", screen.session.stats())
	print("RESULT: ", "PASS" if result == "PASS" else "FAIL")
	screen.free()
	quit(0 if result == "PASS" else 1)
