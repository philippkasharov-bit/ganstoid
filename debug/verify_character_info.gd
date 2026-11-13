## CI1: one Character Info window with Info / Skills / Health tabs, Zomboid's.
## K opens it on Info, H on Health; the same key again closes it; the other
## key switches tab instead of closing.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var ok := true
	var win := CharacterWindow.new()
	root.add_child(win)
	win.setup(World.new(), Vector2(10, 10))
	await process_frame
	ok = ok and not win.visible and win._tabs._pages.size() == 3
	win.open_tab(CharacterWindow.TAB_INFO)
	ok = ok and win.visible and win._tabs.current == CharacterWindow.TAB_INFO and not win.showing_health()
	win.open_tab(CharacterWindow.TAB_HEALTH)   # H while on Info: switch, not close
	ok = ok and win.visible and win.showing_health()
	win.open_tab(CharacterWindow.TAB_HEALTH)   # H again: close
	ok = ok and not win.visible
	win.open_tab(CharacterWindow.TAB_HEALTH)
	win.open_tab(CharacterWindow.TAB_INFO)     # K while on Health: switch
	ok = ok and win.visible and win._tabs.current == CharacterWindow.TAB_INFO
	win.open_tab(CharacterWindow.TAB_INFO)
	ok = ok and not win.visible
	print("CHARACTER_INFO_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
