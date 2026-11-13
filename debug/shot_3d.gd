## R3D0 screenshot: the 3D look test. godot --path . -s debug/shot_3d.gd -- --out=<png> [--size=<ortho m>]
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var preview: Node3D = load("res://core/render3d/city3d_preview.gd").new()
	root.add_child(preview)
	for i in 8:
		await process_frame
	if args.has("size"):
		preview.camera.size = float(args["size"])
		await process_frame
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args.get("out", "/tmp/3d.png"))
	quit()
