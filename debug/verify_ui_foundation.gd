## UI4: the shared widgets build, stay on screen and report picks.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var ok := true
	var win := UiWindow.new()
	root.add_child(win)
	win.setup_window("test", "Inventory", Vector2(5000, 5000), Vector2(300, 200))
	win.body.add_child(UiTheme.label("row"))
	await process_frame
	win.move_to(Vector2(5000, 5000))
	var screen := root.get_visible_rect().size
	ok = _c(ok, 1, win.position == Vector2(5000, 5000).clamp(Vector2.ZERO, (screen - win.size).max(Vector2.ZERO)))
	win.close_window()
	ok = _c(ok, 2, not win.visible)
	var again := UiWindow.new()
	root.add_child(again)
	again.setup_window("test", "Inventory", Vector2.ZERO, Vector2(300, 200))
	ok = _c(ok, 3, again.position == win.position)   # reopens where it was left
	var menu := ContextMenu.new()
	root.add_child(menu)
	var got := [-1]
	menu.picked.connect(func(i: int) -> void: got[0] = i)
	menu.open_at(Vector2(10, 10), [{"text": "Open door"}, {"text": "Lockpick", "enabled": false, "why": "no pick"}])
	await process_frame
	var rows := menu.get_child(0).get_children()
	ok = _c(ok, 4, rows.size() == 2 and (rows[1] as Button).disabled)
	(rows[0] as Button).pressed.emit()
	ok = _c(ok, 5, got[0] == 0 and not menu.visible)
	menu.open_at(Vector2(10, 10), [{"text": "Open door"}, {"text": "Kick in"}])
	await process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	menu._input(key)
	ok = _c(ok, 7, got[0] == 1 and not menu.visible)
	var tip := UiTooltip.new()
	root.add_child(tip)
	tip.show_at(screen - Vector2(2, 2), "Pistol", [["Damage 24", UiTheme.TEXT]], "Cheap 9mm.")
	await process_frame
	ok = _c(ok, 6, tip.position.x >= 0 and (tip.position.x + tip.size.x <= screen.x + 0.5 or tip.position.x == 0))
	print("UI_FOUNDATION_VERIFY: ", "PASS" if ok else "FAIL")
	quit()

func _c(ok: bool, n: int, cond: bool) -> bool:
	if not cond:
		print("check failed: ", n)
	return ok and cond
