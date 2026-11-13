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
	# SK2: grouped skills, Zomboid boxes, an honest hover card.
	var st := PlayerStateData.new()
	st.skills = {&"melee": 140.0}
	win._skills.refresh(st)
	ok = ok and win._skills.get_child_count() == 1 + Skills.GROUPS.size() + Skills.NAMES.size()
	ok = ok and Skills.progress(140.0) == [2, 40.0, 125.0] and Skills.progress(9999.0)[0] == Skills.MAX_LEVEL
	var c := SkillsPanel.card(&"melee", 140.0)
	ok = ok and c[0][0] == "Level 2 / 10" and c[1][0] == "XP 40 / 125 to the next" and c[2][0].begins_with("+10%")
	var grouped := 0
	for g in Skills.GROUPS:
		grouped += g[1].size()
	ok = ok and grouped == Skills.NAMES.size()
	print("CHARACTER_INFO_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
