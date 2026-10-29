extends SceneTree

## Viewport, touch navigation and preference regressions over the actual board.
var screen
var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	screen = load("res://Scenes/ui/DuelBoard.tscn").instantiate()
	root.add_child(screen)
	for i in range(1000):
		if not screen.current.is_empty(): break
		await process_frame
	_check(not screen.current.is_empty(), "real session presents an opening prompt")
	screen.reveal_board()
	var original_prompt: Dictionary = screen.current.duplicate(true)
	var original_viewer: int = screen.viewer
	root.size = Vector2i(1600, 900)
	screen._sync_window_layout()
	await process_frame
	_check(not screen._compact_layout, "desktop presents three simultaneous panels")
	_check(screen._left_panel.visible and screen._right_panel.visible and screen._middle_scroll.visible, "desktop panels visible")
	_check(not screen._tabs.visible, "desktop does not show redundant tabs")
	for dimensions in [Vector2i(1280, 720), Vector2i(800, 600), Vector2i(480, 900), Vector2i(390, 844), Vector2i(360, 800), Vector2i(320, 640)]:
		root.size = dimensions
		screen._sync_window_layout()
		await process_frame
		await process_frame
		_check(screen._motion_button.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(screen._motion_button.get_global_rect()), "reduced-motion control remains visible and reachable at %s" % dimensions)
		_check(screen._audio_button.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(screen._audio_button.get_global_rect()), "sound settings remain reachable at %s" % dimensions)
		screen._audio_button.pressed.emit()
		await process_frame
		_check(screen._audio_dialog.visible and screen._audio_dialog.size.x <= dimensions.x and screen._audio_dialog.size.y <= dimensions.y, "sound settings fit viewport at %s" % dimensions)
		_check(screen._audio_slider.size.y >= 48 and screen._audio_toggle.size.y >= 48, "sound controls retain touch-sized targets at %s" % dimensions)
		screen._audio_dialog.hide()
		_check(screen._compact_layout and screen._tabs.visible, "compact navigation at %s" % dimensions)
		if dimensions.x < 700:
			_check(screen._board.get_combined_minimum_size().x <= screen._middle_scroll.size.x - 8, "all five field lanes fit narrow viewport at %s" % dimensions)
		_check(root.content_scale_size.x == dimensions.x, "small window preserves native-scale touch targets at %s" % dimensions)
		for tab in [1, 2, 0, 1, 0]:
			(screen._tabs.get_child(tab) as Button).pressed.emit()
			await process_frame
			_check(screen._middle_scroll.visible == (tab == 0) and screen._right_panel.visible == (tab == 1) and screen._left_panel.visible == (tab == 2), "exactly one compact panel shown at tab %d" % tab)
			_check(screen._animations.visible == (tab == 0), "actors never overlay another compact tab")
		_check(screen.current == original_prompt and screen.viewer == original_viewer, "resize/navigation preserve authoritative prompt and viewer")
		_check(screen._tabs.get_global_rect().end.x <= float(dimensions.x) + 1, "touch tabs fit viewport at %s" % dimensions)
		for button in screen._tabs.get_children():
			_check(button.size.y >= 48, "navigation targets are at least 48 logical pixels")
	var opponent: Dictionary = screen.view["players"][1 - screen.viewer]
	var saved_hand: Array = opponent["hand"]
	var many_backs: Array = []
	for i in range(20): many_backs.append({"hidden": true, "id": -1000 - i})
	opponent["hand"] = many_backs
	screen._render_board()
	await process_frame
	await process_frame
	_check(screen._board.get_combined_minimum_size().x <= screen._middle_scroll.size.x - 8, "large opponent hands wrap without widening the phone board")
	opponent["hand"] = saved_hand
	screen._render_board()
	var own_hand: Array = screen.view["players"][screen.viewer]["hand"]
	screen._inspect(own_hand[0])
	_check(screen._active_tab == 2 and screen._left_panel.visible, "tap card opens visible inspector on a narrow screen")
	screen.cover_board()
	_check(not screen._content.visible and not screen._tabs.visible and not screen._animations.visible, "cover hides all responsive panels and actors")
	screen.reveal_board()
	_check(screen._active_tab == 0 and screen._middle_scroll.visible, "handoff always reopens the arena rather than stale card details")
	screen._select_tab(1)
	screen._popup_confirmation(screen._restart_dialog)
	await process_frame
	_check(screen._restart_dialog.size.x <= root.size.x, "confirmation fits narrow viewport")
	screen._restart_dialog.hide()
	screen._popup_audio_settings()
	root.size = Vector2i(390, 844)
	screen._sync_window_layout()
	await process_frame
	_check(screen._audio_dialog.visible and screen._audio_dialog.size.x <= 390, "an open sound dialog adapts to window resize")
	screen._audio_dialog.hide()
	var preference_before: bool = screen._animations.reduced_motion
	screen._set_reduced_motion(true)
	screen._animations.set_reduced_motion(false)
	screen._load_presentation_preferences()
	_check(screen._animations.reduced_motion and screen._motion_button.button_pressed, "reduced-motion preference survives reload")
	screen._set_reduced_motion(preference_before)
	for button in screen._choices.get_children():
		if button is Button: _check(button.custom_minimum_size.y >= 48, "legal move is a touch-sized target")
	root.size = Vector2i(1600, 900)
	screen._sync_window_layout()
	_check(screen._left_panel.visible and screen._right_panel.visible and screen._middle_scroll.visible, "returning to desktop restores all panels")
	print("Visual layout: %d assertions" % assertions)
	for failure in failures: print("FAIL: ", failure)
	print("RESULT: ", "PASS" if failures.is_empty() else "FAIL")
	screen.free()
	await create_timer(1.1).timeout
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition: failures.append(description)
