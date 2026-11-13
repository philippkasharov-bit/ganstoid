## R3D screenshot: the 3D look test. godot --path . -s debug/shot_3d.gd -- --out=<png> [--size=<ortho m>] [--radius=<m>]
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var preview: Node3D = load("res://core/render3d/city3d_preview.gd").new()
	if args.has("radius"):
		preview.radius_m = float(args["radius"])
	root.add_child(preview)
	for i in 8:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	print("R3D: built in %d ms, %d chunk meshes, %.1f ms a frame" % [preview.build_ms, preview.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Chunk")).size(), (Time.get_ticks_usec() - t0) / 60000.0])
	if args.has("size"):
		preview.camera.size = float(args["size"])
		await process_frame
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args.get("out", "/tmp/3d.png"))
	quit()
