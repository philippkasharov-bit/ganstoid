## Screenshot tool for the game scene (not a check): loads scenes/main.tscn,
## waits for the street routes, fast-forwards the sim, saves a PNG.
## Run: godot --rendering-driver opengl3 --path . -s debug/shot_main.gd -- --out=<png> [--sim=<seconds>] [--zoom=<px/m>] [--hour=<0-23>] [--aim] [--bag]
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Engine.set_meta("skip_new_game", true)   # O1: screenshots start straight in (Normal / Street life)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run(main, args)

func _run(main: Node, args: Dictionary) -> void:
	var driver: Node = main.get_node("WorldDriver")
	while SimNav.active == null or not SimNav.active.is_ready():
		await process_frame
	for i in 3:
		await process_frame   # let the HUD see the streets loaded once
	if args.has("hour"):
		driver.world.tick = SimClock.hours(float(args["hour"]))
	for i in int(float(args.get("sim", "20")) * SimClock.TICKS_PER_SECOND):
		driver.world.step(1.0 / SimClock.TICKS_PER_SECOND)
	if args.has("zoom"):
		main.get_node("Camera2D").zoom = Vector2.ONE * float(args["zoom"])
	for i in 4:
		await process_frame
	if args.has("openings"):   # DW2 look: the nearest buildings broken into / boarded
		var me1: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var near: Array = []
		for e in driver.world.entities.values():
			var b: BuildingData = e.get_component(ComponentNames.BUILDING)
			if b != null and b.position.distance_to(me1.position) < 60.0:
				near.append(b)
		near.sort_custom(func(a: BuildingData, c: BuildingData) -> bool: return a.position.distance_to(me1.position) < c.position.distance_to(me1.position))
		if near.size() >= 3:
			near[0].door_kicked = true
			near[1].windows_broken = 2
			near[2].windows_boarded = true
		for i in 70:
			await process_frame
	if args.has("inside"):   # LT1 look: just broke into the nearest house, bag open on its drawers
		var me2: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var st2: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var best: BuildingData = null
		for e in driver.world.entities.values():
			var b: BuildingData = e.get_component(ComponentNames.BUILDING)
			if b != null and b.building_type == GanstoidEnums.BuildingType.RESIDENCE and b.id != me2.home_building_id and (best == null or b.position.distance_to(me2.position) < best.position.distance_to(me2.position)):
				best = b
		me2.position = best.position
		driver.world.reindex_position(me2.id)
		st2.inside_id = best.id
		st2.inventory = {&"water": 1, &"bandage": 2}
		st2.inventory_open = true
		for i in 10:
			await process_frame
	if args.has("menu"):   # UI1 look: the E menu open
		var st: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		st.menu_title = "Crime"
		st.menu_options = PackedStringArray(["Mug them (knife out)", "Pickpocket", "Rob the place", "Break in", "Spray your tag"])
		st.menu_notes = PackedStringArray(["3 watching", "", "", "", ""])
		st.menu_parent = PackedStringArray(["Shop & deals  ›", "Talk  ›", "Crime  ›", "Crew  ›", "Car  ›"])   # WM1: the fly-out look
		st.menu_parent_on = 2
		root.get_viewport().warp_mouse(Vector2(420, 220))
		st.menu_serial += 1
		await process_frame
		await process_frame
	if args.has("hotbar"):   # HB1 look: a loaded belt, pistol in hand
		var sh: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		sh.inventory = {&"bat": 1, &"knife": 1, &"pistol": 1, &"bandage": 4, &"burrito": 2, &"water": 1}
		sh.weapon = &"pistol"
		sh.ammo = 11
		for i in 15:
			await process_frame
	if args.has("bag"):   # UI5 look: the bag open with a mixed load, hovering the pistol line
		var st: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		st.inventory = {&"water": 2, &"soda": 1, &"chips": 2, &"burrito": 1, &"bandage": 7, &"bat": 1, &"knife": 1, &"pistol": 1, &"weed": 14}
		st.ammo = 24
		var me0: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		st.ground = [{"id": &"coffee", "n": 2, "pos": me0.position + Vector2(1.2, 0.5)}, {"id": &"bandage", "n": 3, "pos": me0.position + Vector2(-1.0, 0.8)}]
		BodyParts.ensure(st)
		st.skills = {&"melee": 140.0, &"theft": 30.0, &"driving": 410.0}
		st.body["r_forearm"] = {"hp": 0.4, "wound": "laceration", "bleeding": true, "bandaged": false, "bandage_age": 0.0, "infection": 0.0}
		st.body["l_shin"] = {"hp": 0.25, "wound": "fracture", "bleeding": false, "bandaged": false, "bandage_age": 0.0, "infection": 0.0}
		st.body["torso_upper"] = {"hp": 0.7, "wound": "bullet wound", "bleeding": false, "bandaged": true, "bandage_age": 1.5, "infection": 0.0}
		st.body["l_hand"] = {"hp": 0.6, "wound": "laceration", "bleeding": false, "bandaged": false, "bandage_age": 0.0, "infection": 1.0}
		st.body["head"] = {"hp": 0.88, "wound": "bruise", "bleeding": false, "bandaged": false, "bandage_age": 0.0, "infection": 0.0}
		for n in main.get_node("HudLayer").get_children():
			if n is CharacterWindow:
				n.open_tab(CharacterWindow.TAB_HEALTH)
				n.position = Vector2(500, 60)
				n._health._select("r_forearm")
				if args.has("skills"):   # SK2 look: the Skills tab with melee's card
					n._tabs.pick(1)
					n._skills.refresh(st)
					await process_frame
					n._skills.get_child(3).mouse_entered.emit()
		st.timed = {"item": &"burrito", "start": driver.world.tick - 60, "done": driver.world.tick + 120}
		var me: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		me.hunger = 0.25
		me.thirst = 0.1
		me.fatigue = 0.4
		me.health = 0.6
		me.bleeding = true
		st.inventory_open = true
		for i in 3:
			await process_frame
		var win: InventoryWindow = null
		for n in main.get_node("HudLayer").get_children():
			if n is InventoryWindow:
				win = n
		for i in 3:
			await process_frame
		st.law_tier = 1
		root.get_viewport().warp_mouse(Vector2(370, 330))
		await process_frame
		win._show_tip(&"pistol", Vector2(330, 230))
		await process_frame
	if args.has("aim"):   # combat look: pistol raised toward a point right of the player, one shot
		var player: Entity = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID]
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		state.weapon = &"pistol"
		root.get_viewport().warp_mouse(root.get_viewport().get_visible_rect().size * 0.5 + Vector2(260, -90))
		Input.action_press(PlayerInputSystem.AIM_ACTION)   # through the real input path
		await process_frame
		Input.action_press(PlayerInputSystem.ATTACK_ACTION)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args.get("out", "/tmp/main.png"))
	quit()
