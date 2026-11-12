## UI4: screenshot of the shared widgets for review.
extends SceneTree
func _initialize() -> void:
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.36, 0.33)
	bg.size = Vector2(1600, 1000)
	root.add_child(bg)
	var win := UiWindow.new()
	root.add_child(win)
	win.setup_window("demo", "Backpack", Vector2(60, 60), Vector2(360, 240))
	for t in ["Pistol (9mm)        1.2 kg", "Bandage x3           0.3 kg", "Cash $420"]:
		win.body.add_child(UiTheme.label(t))
	var menu := ContextMenu.new()
	root.add_child(menu)
	menu.open_at(Vector2(520, 120), [{"text": "Open door"}, {"text": "Knock"}, {"text": "Lockpick", "enabled": false, "why": "need a pick"}, {"text": "Kick in"}])
	var tip := UiTooltip.new()
	root.add_child(tip)
	tip.show_at(Vector2(760, 300), "Pistol (9mm)", [["Damage 24", UiTheme.TEXT], ["Condition 7/10", UiTheme.GOOD], ["Loud", UiTheme.BAD]], "Cheap street piece. Jams when worn.")
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
