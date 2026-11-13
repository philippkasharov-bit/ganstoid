## R3D screenshot: the 3D look test. godot --path . -s debug/shot_3d.gd -- --out=<png> [--size=<ortho m>] [--radius=<m>] [--sim=<seconds of sim to run first>]
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var preview: Node3D = load("res://core/render3d/city3d_preview.gd").new()
	if args.has("radius"):
		preview.radius_m = float(args["radius"])
	preview.live_sim = args.has("sim")
	root.add_child(preview)
	if preview.live_sim:   # R3D3: let the routes load, then the morning rush run a while
		while SimNav.active == null or not SimNav.active.is_ready():
			await process_frame
		for i in int(float(args["sim"]) * Engine.physics_ticks_per_second):
			await physics_frame
		print("R3D3: %d people, %d cars drawn" % [preview.people3d.shown_people, preview.people3d.shown_cars])
		var me: NPCData = preview.driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var outside: int = preview.driver.world.get_entities_with_component(ComponentNames.NPC).values().filter(func(e: Entity) -> bool: return not (e.get_component(ComponentNames.NPC) as NPCData).indoors).size()
		print("R3D3: player %s (spawn %s) indoors=%s; %d people outdoors in the district" % [me.position, preview.centre, me.indoors, outside])
		preview.camera.position += Vector3(me.position.x - preview.centre.x, 0, me.position.y - preview.centre.y)   # look at the player
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
