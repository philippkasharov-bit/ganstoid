## UI6 validator: a panel goes where the player dragged it (its default plus
## the offset) but never off screen; J/O-style hiding toggles and is kept;
## "Reset HUD layout" puts everything back; a dragged window's spot is kept;
## the pushes are rare (a quarter of days at most, days apart).
extends SceneTree

func _initialize() -> void:
	var ok := true
	var saved := FileAccess.get_file_as_string(HudLayout.PATH) if FileAccess.file_exists(HudLayout.PATH) else ""
	var c := Control.new()
	root.add_child(c)
	await process_frame
	c.size = Vector2(100, 50)
	root.size = Vector2i(1280, 720)   # a headless window is 64 x 64
	await process_frame
	HudLayout.reset()
	HudLayout._loaded = false
	ok = _check(HudLayout.place(c, "pager", Vector2(300, 20)) == Vector2(300, 20), "no offset: the default spot") and ok
	HudLayout.move("pager", Vector2(-40, 60))
	ok = _check(HudLayout.place(c, "pager", Vector2(300, 20)) == Vector2(260, 80), "dragged: the default plus the offset") and ok
	HudLayout.move("pager", Vector2(-9000, 0))
	ok = _check(HudLayout.place(c, "pager", Vector2(300, 20)).x == 0.0, "never off screen") and ok
	HudLayout.toggle("minimap")
	HudLayout._loaded = false
	HudLayout._hidden.clear()
	ok = _check(not HudLayout.shown("minimap"), "hiding is kept") and ok
	HudLayout.save_window("bag", Vector2(222, 111))
	ok = _check(HudLayout.window_pos("bag", Vector2(1, 1)) == Vector2(222, 111), "a dragged window keeps its spot") and ok
	HudLayout.reset()
	ok = _check(HudLayout.shown("minimap") and HudLayout.place(c, "pager", Vector2(300, 20)) == Vector2(300, 20) and HudLayout.window_pos("bag", Vector2(1, 1)) == Vector2(1, 1), "reset puts it all back") and ok
	ok = _check(CornerWarSystem.PUSH_CHANCE <= 0.25 and CornerWarSystem.PUSH_GAP_DAYS >= 2 and CornerWarSystem.SQUAD <= 2, "pushes are rare and small") and ok
	if saved != "":
		var f := FileAccess.open(HudLayout.PATH, FileAccess.WRITE)
		f.store_string(saved)
	if ok:
		print("UI_LAYOUT_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("UI_LAYOUT_VERIFY: FAIL - ", what)
	return good
