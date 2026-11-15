extends SceneTree
func _initialize() -> void:
	Engine.set_meta("skip_new_game", true)
	Engine.set_meta("seed", 4242)   # QA4: same city every run
	Engine.set_meta("no_save", true)   # QA4: never read or write a save
	root.add_child(load("res://scenes/main.tscn").instantiate())
	for i in 4:   # QA4: the title art is only up while the streets load (~2 s)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
