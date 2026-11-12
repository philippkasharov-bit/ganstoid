extends SceneTree
func _initialize() -> void:
	Engine.set_meta("skip_new_game", true)
	root.add_child(load("res://scenes/main.tscn").instantiate())
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
