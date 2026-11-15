extends SceneTree
func _initialize() -> void:
	Engine.set_meta("seed", 4242)   # QA4: same city every run
	Engine.set_meta("no_save", true)   # QA4: never read a save, so the new-game choice shows
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 120:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
