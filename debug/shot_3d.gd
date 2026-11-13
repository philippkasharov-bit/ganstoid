## R3D screenshot: the 3D look test. godot --path . -s debug/shot_3d.gd -- --out=<png> [--size=<ortho m>] [--radius=<m>] [--sim=<seconds of sim to run first>] [--behind (R3D4: stand the player behind the nearest tall building)] [--inside (R3D5: in the nearest house)] [--turn=<quarters>] [--hour=<0-24> (R3D10)] [--home (R3D14: walk in through your own front door)]
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
	if args.has("hour"):
		preview.day_night.hour_override = float(args["hour"])
	if preview.live_sim:   # R3D3: let the routes load, then the morning rush run a while
		while SimNav.active == null or not SimNav.active.is_ready():
			await process_frame
		for i in int(float(args["sim"]) * Engine.physics_ticks_per_second):
			await physics_frame
		print("R3D3: %d people, %d cars drawn" % [preview.people3d.shown_people, preview.people3d.shown_cars])
		var me: NPCData = preview.driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var outside: int = preview.driver.world.get_entities_with_component(ComponentNames.NPC).values().filter(func(e: Entity) -> bool: return not (e.get_component(ComponentNames.NPC) as NPCData).indoors).size()
		print("R3D3: player %s (spawn %s) indoors=%s; %d people outdoors in the district" % [me.position, preview.centre, me.indoors, outside])
		if args.has("home"):
			await _walk_home(preview, me)
		if args.has("inside"):
			me.position = _in_house(me.position)
		if args.has("behind"):
			me.position = _behind_building(me.position)
			for i in 20:   # step back out of any neighbour we landed in
				if preview.people3d.footprints.at(me.position).is_empty():
					break
				me.position += Vector2(1, 1).normalized() * 0.5
		preview.rig.look_at_map(me.position)
	for i in 8:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	print("R3D: built in %d ms, %d chunk meshes, %.1f ms a frame" % [preview.build_ms, preview.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Chunk")).size(), (Time.get_ticks_usec() - t0) / 60000.0])
	if args.has("turn"):   # R3D6: the view turned by quarters
		preview.rig.turn(int(args["turn"]))
		for i in 40:
			await process_frame
	if args.has("size"):
		preview.rig.target_size = float(args["size"])
		for i in 40:
			await process_frame
		await process_frame
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args.get("out", "/tmp/3d.png"))
	quit()

## Just past the far (north-west, away from the camera) side of the nearest 2+ storey building.
func _behind_building(near: Vector2) -> Vector2:
	var away := Vector2(-1, -1).normalized()
	var best: Dictionary = {}
	var best_d := INF
	for b in CityData.load_file().buildings:
		var d := (b["poly"][0] as Vector2).distance_squared_to(near)
		if int(b.get("levels", 1)) >= 2 and d < best_d:
			best_d = d
			best = b
	var poly: PackedVector2Array = best["poly"]
	var mid := Vector2.ZERO
	var far := -INF
	for p in poly:
		mid += p / poly.size()
		far = maxf(far, p.dot(away))
	return mid + away * (far - mid.dot(away) + 1.2)

## The middle of the nearest house's footprint.
func _in_house(near: Vector2) -> Vector2:
	var best := Vector2.ZERO
	for b in CityData.load_file().buildings:
		var poly: PackedVector2Array = b["poly"]
		var mid := Vector2.ZERO
		for p in poly:
			mid += p / poly.size()
		if b["kind"] == "house" and Geometry2D.is_point_in_polygon(mid, poly) and mid.distance_squared_to(near) < best.distance_squared_to(near):
			best = mid
	return best

## R3D14: stand outside your own front door and walk in through it.
func _walk_home(preview: Node, me: NPCData) -> void:
	var st: PlayerStateData = preview.driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	for b in preview.city_data.buildings:
		if b["id"] == me.home_building_id:
			var l := InteriorLayout.of(b)
			var mid := l.door_a.lerp(l.door_b, 0.5)
			var out := (l.door_b - l.door_a).normalized().orthogonal()
			if Geometry2D.is_point_in_polygon(mid + out * 0.5, l.poly):
				out = -out
			me.position = mid + out * 1.5
			for i in 40:
				me.position = Indoors.step(preview.driver.world, me, st, -out * 0.1)
				await physics_frame
			print("R3D14: walked home: inside %s (door %s-%s, at %s, kind %s)" % [Geometry2D.is_point_in_polygon(me.position, l.poly), l.door_a, l.door_b, me.position, b["kind"]])
			return
	print("R3D14: home is not a city building")
