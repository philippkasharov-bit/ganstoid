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
	if args.has("hour"):
		driver.world.tick = SimClock.hours(float(args["hour"]))
	for i in int(float(args.get("sim", "20")) * SimClock.TICKS_PER_SECOND):
		driver.world.step(1.0 / SimClock.TICKS_PER_SECOND)
	if args.has("zoom"):
		main.get_node("Camera2D").zoom = Vector2.ONE * float(args["zoom"])
	for i in 4:
		await process_frame
	if args.has("menu"):   # UI1 look: the E menu open
		var st: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		st.menu_options = PackedStringArray(["Shop here", "Mug them (knife out)", "Pickpocket", "Recruit into your crew", "Get in the car", "Spray your tag"])
		await process_frame
		await process_frame
	if args.has("bag"):   # UI5 look: the bag open with a mixed load, hovering the pistol line
		var st: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		st.inventory = {&"water": 2, &"burrito": 1, &"bandage": 3, &"knife": 1, &"pistol": 1, &"ammo": 2, &"weed": 4}
		st.ammo = 24
		var me: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		me.hunger = 0.25
		me.thirst = 0.1
		me.fatigue = 0.4
		me.health = 0.6
		me.bleeding = true
		st.skills = {&"melee": 140.0, &"theft": 30.0, &"driving": 410.0}
		for n in main.get_node("HudLayer").get_children():
			if n is SkillsWindow:
				n.visible = true
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
		win._show_tip(&"pistol")
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
