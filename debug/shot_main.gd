## Screenshot tool for the game scene (not a check): loads scenes/main.tscn,
## waits for the street routes, fast-forwards the sim, saves a PNG.
## Run: godot --rendering-driver opengl3 --path . -s debug/shot_main.gd -- --out=<png> [--sim=<seconds>] [--zoom=<px/m>] [--hour=<0-23>] [--aim] [--bag] [--map]
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Engine.set_meta("seed", int(OS.get_environment("SHOT_SEED")) if OS.has_environment("SHOT_SEED") else 4242)   # QA4: same city every run
	Engine.set_meta("no_save", true)   # QA4: a picture never writes (or reads back) a save
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
	if args.has("uiscale"):   # UI2: the UI size setting
		root.content_scale_factor = float(args["uiscale"])
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
	if args.has("motion"):   # A1-A3 look: just ate (Hungry -> Peckish, +Food), then got hit
		var mm: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		mm.hunger = 0.2
		mm.thirst = 0.25
		for i in 30:
			await process_frame
		mm.hunger = 0.45
		for i in 20:
			await process_frame
		var ms2: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		ms2.inventory = {&"knife": 1, &"pistol": 1, &"bandage": 2}
		ms2.ammo = 12
		for i in 10:
			await process_frame
		CombatSystem._hurt(driver.world, mm, {"damage": 0.2})
		mm.cash += 250                                   # A4: counts up in green
		ms2.weapon = &"pistol"                           # A8: the frame pops
		Skills.train(driver.world, ms2, &"melee", 30.0)  # A7: "Melee 1" in gold
		for i in 5:
			await process_frame
	if args.has("money"):   # E5 look: the money map, a few shops gone under, the menu reading a place
		for n in main.get_children():
			if "mode" in n and n.has_method("_draw_money"):
				n.mode = 2
				n.visible = true
				n.z_index = 20
				n.queue_redraw()
		var shut := 0
		for b in BusinessSystem.all_buildings(driver.world):
			if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and shut < 12 and b.position.distance_to(driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC).position) < 500.0:
				b.status = 2
				shut += 1
		var sm: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		sm.menu_title = "Crime"
		sm.menu_options = PackedStringArray(["Rob the place", "Pick the lock", "Smash a window", "Mug them (knife out)"])
		sm.menu_notes = PackedStringArray(["busy · camera", "nearly broke · hit lately", "nearly broke · hit lately", ""])
		for i in 4:
			await process_frame
	if args.has("pause"):   # PM1 look: the Esc menu with the controls shown
		for n in main.get_node("HudLayer").get_children():
			if n is PauseMenu:
				n._open()
				n._toggle_controls(true)
		for i in 4:
			await process_frame
	if args.has("prompt"):   # UI4 look: someone in reach, the prompt over them
		var pn: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		for e in driver.world.get_entities_with_component(ComponentNames.NPC).values():
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if n != pn and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_crew or n.is_down) and n.gang_id == &"":
				n.position = pn.position + Vector2(1.6, 0.8)
				n.indoors = false
				n.is_busy = true   # stands still for the picture
				driver.world.reindex_position(n.id)
				break
		for i in 4:
			await process_frame
	if args.has("bark"):   # ME1 look: someone you robbed knows you again
		var bp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var bs: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		for e in driver.world.get_entities_with_component(ComponentNames.NPC).values():
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if n != bp and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_crew or n.is_down) and n.gang_id == &"":
				n.position = bp.position + Vector2(3.0, 1.0)
				n.indoors = false
				n.is_busy = true
				driver.world.reindex_position(n.id)
				MemorySystem.remember(driver.world, bs, n.id, "robbed")
				MemorySystem.bark(driver.world, bs, n.id, "That's him! He robbed me!", -1)
				bs.barks[-1]["until"] = driver.world.tick + 100000
				break
		for i in 4:
			await process_frame
	if args.has("trial") or args.has("court"):   # CT1 look: charged with four witnesses; --court: the court has sat
		var tp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var ts: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var deeds := ["robbed", "saw_crime", "saw_crime", "robbed"]
		for e in driver.world.get_entities_with_component(ComponentNames.NPC).values():
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if deeds.is_empty():
				break
			if n != tp and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_crew or n.is_down) and n.gang_id == &"" and n.position.distance_to(tp.position) < 400.0:
				MemorySystem.remember(driver.world, ts, n.id, deeds.pop_back())
				if deeds.size() == 1:
					n.fear = 1.0   # one too scared to come
		ts.case_evidence = 45.0
		CourtSystem.charge(driver.world, tp, ts)
		if args.has("court"):
			CourtSystem.hold(driver.world, tp, ts)
		for i in 6:
			await process_frame
	if args.has("crew"):   # CA1 look: three crew, one asking for a wage
		var cp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var cs: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var natures := [&"loyal", &"climber", &"greedy"]
		for e in driver.world.get_entities_with_component(ComponentNames.NPC).values():
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if natures.is_empty():
				break
			if n != cp and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_crew or n.is_down) and n.gang_id == &"":
				n.is_crew = true
				n.ambition = natures.pop_back()
				n.loyalty = 0.55 + 0.1 * natures.size()
				cs.crew_ids.append(n.id)
		cs.crew_wages[cs.crew_ids[1]] = 30
		CrewAmbitionSystem._ask(driver.world, cs, driver.world.entities[cs.crew_ids[0]].get_component(ComponentNames.NPC), "raise", 30, "I'm worth more than this. $%d a day, or I walk.")
		for i in 4:
			await process_frame
	if args.has("grow"):   # BZ1 look: a grow at home mid-way, a harvest drying, a stamp
		var gs: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var t: int = driver.world.tick
		gs.grow = {"tents": 1, "lamp": 2, "fan": true, "filter": false, "plants": [
			{"strain": &"seeds_kush", "at": t - SimClock.hours(50), "watered": t - SimClock.hours(2), "fed": 2, "care": 1.0},
			{"strain": &"seeds_kush", "at": t - SimClock.hours(30), "watered": t - SimClock.hours(14), "fed": 1, "care": 0.9},
			{"strain": &"seeds_haze", "at": t - SimClock.hours(10), "watered": t - SimClock.hours(3), "fed": 0, "care": 1.0},
			{"strain": &"seeds_mids", "at": t - SimClock.hours(5), "watered": t - SimClock.hours(3), "fed": 0, "care": 1.0}],
			"drying": [{"units": 6, "q": 4.2, "strain": "seeds_kush", "ready": t + SimClock.hours(4)}]}
		gs.inventory[&"weed"] = 12
		gs.product = {"q": 3.6, "strain": "seeds_kush"}
		gs.brand = "Blue Dragon"
		gs.brand_rep = 0.35
		for i in 4:
			await process_frame
	if args.has("biz"):   # BZ2 look: a grow with a grower, an owned shop waiting for a manager
		var bp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var bs: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		bs.grow = {"tents": 2, "lamp": 2, "fan": true, "filter": true, "plants": [], "drying": [], "stash": {"units": 14, "q": 3.9, "strain": "OG Kush"}, "stock": {&"seeds_kush": 6, &"plant_food": 4}}
		var home: BuildingData = driver.world.entities[bp.home_building_id].get_component(ComponentNames.BUILDING)
		var gc := StaffSystem.candidates(driver.world, bs, home.position)
		if not gc.is_empty():
			StaffSystem.hire(driver.world, bs, gc[0], &"grow", "grower")
		for b in BusinessSystem.all_buildings(driver.world):
			if b.daily_revenue > 0 and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.position.distance_to(bp.position) < 300.0:
				b.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
				BuildingData.ownership_serial += 1
				break
		bs.biz_day = {"shops": 240, "wages": 55}
		for i in 4:
			await process_frame
	if args.has("club"):   # BZ3 look (with --biz): the shop turned into a two-star club with a back room
		var vs: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		for b in BusinessSystem.player_owned(driver.world):
			vs.venues[b.id] = {"kind": "club", "decor": 1, "back_room": true, "last": 412, "back": 260, "fight": true}
			break
		for i in 4:
			await process_frame
	if args.has("table"):   # BZ3 look: at a back-room table at night, a hand of blackjack on
		var tp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var ts: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		ts.gamble = {"place": &"", "stage": "play", "you": [10, 6], "dealer": [12, 4], "line": "Hit or stand?", "bet": 50, "net": 120}
		for b in BusinessSystem.all_buildings(driver.world):
			if GambleSystem.TRADES.has(b.trade) and b.position.distance_to(tp.position) < GambleSystem.LEAVE_M:
				ts.gamble["place"] = b.id
		if ts.gamble["place"] == &"":   # nothing in reach: the game stays up for the picture
			ts.gamble["place"] = tp.home_building_id
			tp.position = (driver.world.entities[tp.home_building_id].get_component(ComponentNames.BUILDING) as BuildingData).position
			driver.world.reindex_position(tp.id)
		for i in 4:
			await process_frame
	if args.has("cook"):   # BZ4 look: a cook under way, the heat in the green
		var ks: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		ks.cook = {"heat": 0.66, "t": 8.0, "green": 6.0, "boxes": 5}
		driver.paused = true   # held still for the picture
		for i in 4:
			await process_frame
	if args.has("connect"):   # BZ4 look: a Soldier with drugs of every grade, the connect's offers
		var cs2: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		AdminSystem.run(driver.world, "rank_up", null, driver.world.tick)
		AdminSystem.run(driver.world, "rank_up", null, driver.world.tick)
		cs2.inventory[&"pills"] = 24
		cs2.inventory[&"meth"] = 10
		cs2.inventory[&"coke"] = 20
		cs2.products = {&"pills": 2.7, &"meth": 4.8, &"coke": 4.0, "pills_kind": "pill_powder"}
		cs2.prices = {&"coke": 140}
		for i in 4:
			await process_frame
	if args.has("rings") or args.has("deal"):   # UI7 look: people around you marked by who they are to you; --deal: selling to one
		var rp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var rs: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var spots := [Vector2(3, 1), Vector2(-3, 2), Vector2(2, -3), Vector2(-2, -2), Vector2(5, 3)]
		var deeds := ["helped", "robbed", "", "good_product", "threatened"]
		var placed := []
		for e in driver.world.get_entities_with_component(ComponentNames.NPC).values():
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if placed.size() >= spots.size():
				break
			if n != rp and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_crew or n.is_down) and n.gang_id == &"":
				var i := placed.size()
				n.position = rp.position + spots[i]
				n.indoors = false
				n.is_busy = true
				driver.world.reindex_position(n.id)
				if deeds[i] == "":
					n.is_crew = true
				else:
					MemorySystem.remember(driver.world, rs, n.id, deeds[i])
					if deeds[i] == "good_product":
						MemorySystem.remember(driver.world, rs, n.id, deeds[i])
				placed.append(n)
		if args.has("deal"):
			rs.inventory[&"weed"] = 14
			rs.inventory[&"pills"] = 8
			rs.product = {"q": 4.3, "strain": "seeds_kush"}
			rs.products = {&"pills": 2.8, "pills_kind": "pill_powder"}
			placed[3].position = rp.position + Vector2(1.2, 0.4)
			driver.world.reindex_position(placed[3].id)
			TradeSystem.open(rs, "deal", placed[3].id)
			rs.trade["line"] = "Hand to hand: $41."
			rs.trade["tone"] = 1
		for i in 6:
			await process_frame
	if args.has("pawn"):   # UI7 look: the pawn window with a haul from a house
		var pp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var ps: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		ps.inventory = {&"watch": 2, &"gold_chain": 1, &"vcr": 1, &"walkman": 1, &"jordans": 1}
		ps.trade = {"mode": "pawn", "who": pp.home_building_id, "line": "", "tone": 0}
		for i in 6:
			await process_frame
	if args.has("loans"):   # BZ5 look: two people asking, three on the book (one late)
		var lp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var ls: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var ids := []
		for e in driver.world.get_entities_with_component(ComponentNames.NPC).values():
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if n != lp and not (n.is_cop or n.is_crew or n.is_dealer or n.is_down) and n.gang_id == &"" and n.position.distance_to(lp.position) < 300.0:
				ids.append(n.id)
			if ids.size() == 5:
				break
		ls.loan_asks = [{"who": ids[0], "amount": 300, "rate": 0.25}, {"who": ids[1], "amount": 800, "rate": 0.4}]
		ls.loans = [{"who": ids[2], "principal": 200, "total": 260, "owed": 150, "paid": 110, "day": 0, "due": 7, "status": "paying"},
			{"who": ids[3], "principal": 500, "total": 650, "owed": 650, "paid": 0, "day": 0, "due": 1, "status": "late"},
			{"who": ids[4], "principal": 100, "total": 125, "owed": 0, "paid": 125, "day": 0, "due": 7, "status": "paid off"}]
		for i in 4:
			await process_frame
	if args.has("jail"):   # JL1 look: inside, the prison panel
		AdminSystem.run(driver.world, "jail", null, driver.world.tick)
		for i in 4:
			await process_frame
	if args.has("admin"):   # AD1 look: the admin panel on a tab
		for n in main.get_node("HudLayer").get_children():
			if n is AdminWindow:
				n.visible = true
				n._show(String(args["admin"]))
		for i in 4:
			await process_frame
	if args.has("layout"):   # UI6 look: F10 layout mode, the panels outlined
		HudLayout.editing = true
		for i in 4:
			await process_frame
	if args.has("gps"):   # MM1 look: a waypoint set, the GPS line on the minimap
		var gs: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var gn: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		gs.waypoint = gn.position + Vector2(260, 140)
		for i in 6:
			await process_frame
	if args.has("phone"):   # PH1 look: the phone open on Rivals, a message sliding in
		var ph: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		RivalSystem.ensure(driver.world, ph)
		var gs: Array = ph.rivals.keys()
		ph.rivals[gs[0]]["grudge"] = 62.0
		ph.rivals[gs[1]]["grudge"] = 18.0
		ph.rivals[gs[1]]["scars"] = 1
		ph.rank = maxi(ph.rank, 1)   # HS1: a score on, for the Score app
		var pn: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		if HeistSystem.offer(driver.world, ph, pn, driver.world.tick, "store"):
			ph.heist["known"] = true
			ph.heist["stage"] = "cased"
		ph.cash_history = [40, 95, 60, 210, 180, 340]   # UI6: the Bank app's chart
		ph.dirty_cash = 15
		PhoneSystem.push(driver.world, ph, "Unknown number", "Word on the street: %s has your name in their mouth." % ph.rivals[gs[0]]["name"])
		for n in main.get_node("HudLayer").get_children():
			if n is PhoneWindow:
				n.visible = true
				n._app = "" if String(args["phone"]) == "home" else String(args["phone"])
				n._key = ""
		for i in 4:
			await process_frame
	if args.has("stamp"):   # UI3 look: a rank-up stamp slammed down, money floating up
		var st: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var sn: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		for i in 2:
			await process_frame
		sn.cash += 120
		StampView.put(st, "HUSTLER", "NEW RANK")
		for i in 3:   # software drawing is slow (~0.1 s a frame): catch the stamp mid-slam
			await process_frame
	if args.has("paper"):   # NP1/DH1 look: a morning paper after a busy night, today's hustles on the pager
		var ps: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		HustleSystem.roll(driver.world, ps, 1)
		ps.hustles[0]["got"] = 1
		ps.news_today = [["robbery", 180, "Mariachi Plaza"], ["mugged", 35, "Boyle Heights"], ["tagged", 20, "Boyle Heights"]]
		ps.paper = NewsSystem.print_paper(ps, 1)
		ps.paper_serial += 1
		for i in 6:
			await process_frame
	if args.has("sleep"):   # SL1 look: Z when tired: how long?
		var sp: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		sp.fatigue = 0.2
		Input.action_press(PlayerInputSystem.SLEEP_ACTION)
		await physics_frame
		await physics_frame
		Input.action_release(PlayerInputSystem.SLEEP_ACTION)
		root.get_viewport().warp_mouse(Vector2(560, 260))
		for i in 4:
			await process_frame
	if args.has("store"):   # TR1 look: a store counter open with a basket
		var ss: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		var ms: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		for id in driver.world.entities:
			if ShopSystem.counter_kind(driver.world, id) == "shop" and ShopSystem.is_open(driver.world, id):
				ss.store_id = id
				ms.position = PlayerInputSystem._counter_position(driver.world.entities[id])   # stand at the counter
				driver.world.reindex_position(ms.id)
				break
		ms.cash = 30
		ss.inventory = {&"water": 1}
		ss.basket = {&"burrito": 2, &"bandage": 1, &"soda": 1}
		for i in 6:
			await process_frame
	if args.has("hotbar"):   # HB1 look: a loaded belt, pistol in hand
		var sh: PlayerStateData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
		sh.inventory = {&"bat": 1, &"knife": 1, &"pistol": 1, &"bandage": 4, &"burrito": 2, &"water": 1}
		sh.weapon = &"pistol"
		sh.ammo = 11
		var mh: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		mh.hunger = 0.38
		mh.thirst = 0.2
		mh.bleeding = true
		for i in 15:
			await process_frame
		sh.last_message = "Melee up: level 3."   # HT1 look: a line over the head
		sh.message_tone = 1
		sh.message_serial += 1
		for i in 20:
			await process_frame
		for n in main.get_node("HudLayer").get_children():
			if n is Moodles and n.get_child_count() > 1:
				n.get_child(1).mouse_entered.emit()
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
				# BUG-6 was this line (500, 60): the picture put the window over the bag; the game docks it right
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
	if args.has("map"):   # QA4 look: the N map window, centred on you
		for n in main.get_node("HudLayer").get_children():
			if n is CityMapWindow:
				n.visible = true
				n._view.centre_on_player()
		for i in 4:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args.get("out", "/tmp/main.png"))
	quit()
