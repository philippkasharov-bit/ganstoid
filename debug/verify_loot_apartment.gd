## LT2 validator: a block of flats can be looted like a house. At its door the
## E menu's break-in works, and once inside, standing at a kitchen or bedroom
## cupboard shows its contents in Nearby (the bag window).
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var city := TestWorlds.city()
	SimNav.install(city, city.spawn, 300.0)
	await TestWorlds.wait_nav(self, [SimNav.active])
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var tried := 0
	var looted := 0
	for b in city.buildings:
		if b.get("kind", "") != "apartments" or b["poly"][0].distance_to(city.spawn) > 250.0 or tried >= 5:
			continue
		var e: Entity = w.entities.get(b["id"])
		var bd: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
		if bd == null or bd.building_type != GanstoidEnums.BuildingType.RESIDENCE or b["id"] == me.home_building_id:
			continue
		tried += 1
		me.position = bd.position
		w.reindex_position(me.id)
		state.inside_id = &""
		var r := StreetCrime.start_burglary(w, me, state, b["id"], "kick")
		w.tick = state.burglary_done_tick
		var done := StreetCrime.advance_burglary(w, me, state)
		var l := InteriorLayout.of(b)
		var seen := 0
		for f in l.furniture:
			if f["container"] == "":
				continue
			me.position = l.to_map((f["rect"] as Rect2).get_center())
			Vicinity.update_inside(w, me, state)
			for item in Vicinity.near(w, me, state):
				seen += int(item["kind"] == "container")
			if seen > 0:
				break
		print("%s: break-in %s/%s, items at a cupboard %d" % [b["id"], r.get("ok"), done.get("ok"), seen])
		looted += int(r.get("ok", false) and done.get("ok", false) and seen > 0)
	var ok := tried >= 3 and looted == tried
	print("LOOT_APARTMENT_VERIFY: PASS" if ok else "LOOT_APARTMENT_VERIFY: FAIL - %d of %d flats could be looted" % [looted, tried])
	SimNav.uninstall()
	quit(0 if ok else 1)
