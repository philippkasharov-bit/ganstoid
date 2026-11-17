## BZ7 validator: your places are listed and each says what it is (a shop,
## a car wash, a club, a den, a flat); nobody hunting you: no hits; a rival
## hunting you robs a shop's till (message, stamp, the map shows it) and
## his grudge cools a little; a smashed club loses a step of fit-out and
## takes nothing tonight; a robbed den takes nothing tonight; a bouncer,
## your security firm and crew nearby each cut the risk.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	w.tick = SimClock.hours(36.0)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	var shops: Array = []
	for b in BusinessSystem.all_buildings(w):
		if b.daily_revenue > 0 and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			b.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
			shops.append(b)
			if shops.size() == 3:
				break
	BuildingData.ownership_serial += 1
	var flat: BuildingData = null
	for e in w.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.building_type == GanstoidEnums.BuildingType.RESIDENCE and b.id != me.home_building_id:
			flat = b
			break
	state.properties = [flat.id]
	state.fronts[shops[1].id] = "car_wash"
	state.venues[shops[2].id] = {"kind": "club", "decor": 2, "back_room": false, "last": 0}
	var mine := EmpireSystem.places(w, state)
	var letters := []
	for b in [shops[0], shops[1], shops[2], flat]:
		letters.append(EmpireSystem.describe(w, state, b)[0])
	ok = _check(mine.size() == 4 and letters == ["$", "W", "N", "P"], "your places, each with what it is: %s" % str(letters)) and ok
	# nobody hunting: no hits
	RivalSystem.ensure(w, state)
	for g in state.rivals:
		state.rivals[g]["grudge"] = 0.0
	for d in 30:
		EmpireSystem.strike_back(w, state, 10 + d)
	ok = _check(state.empire_hits.is_empty(), "with no rival hunting you, your places are left alone") and ok
	# a rival hunting you, unguarded places
	var g0: StringName = state.rivals.keys()[0]
	state.rivals[g0]["grudge"] = 100.0
	state.properties = []
	state.fronts = {}
	state.venues = {}
	for b in shops:
		b.cash_on_hand = 500
		b.bank = 1000
	var day := 50
	while state.empire_hits.is_empty() and day < 200:
		state.rivals[g0]["grudge"] = 100.0
		EmpireSystem.strike_back(w, state, day)
		day += 1
	var hit_id: StringName = state.empire_hits.keys()[0] if not state.empire_hits.is_empty() else &""
	var hb: BuildingData = w.entities[hit_id].get_component(ComponentNames.BUILDING) if hit_id != &"" else null
	ok = _check(hb != null and hb.cash_on_hand == 0 and hb.bank == 700 and state.stamp.get("text", "") == "HIT" and float(state.rivals[g0]["grudge"]) == 100.0 - EmpireSystem.VENT, "a rival robs a shop of yours: till and $300 of the bank gone ($%d)" % int(state.empire_hits.get(hit_id, {}).get("lost", 0))) and ok
	w.tick = SimClock.day_ticks * (day - 1) + SimClock.hours(10.0)
	ok = _check(String(EmpireSystem.describe(w, state, hb)[2]).contains("hit by"), "the map and the phone show who hit it") and ok
	# a club smashed, a den robbed
	state.venues[shops[2].id] = {"kind": "club", "decor": 2, "back_room": false, "last": 300}
	EmpireSystem.hit(w, state, shops[2], "Spider", HustleSystem.day_of(w.tick))
	VenueSystem.close_night(w, state)
	ok = _check(int(state.venues[shops[2].id]["decor"]) == 1 and int(state.venues[shops[2].id]["last"]) == 0, "a smashed club loses a step of fit-out and takes nothing tonight") and ok
	state.properties = [flat.id]
	state.dens[flat.id] = {"open": true, "last": 250}
	EmpireSystem.hit(w, state, flat, "Spider", HustleSystem.day_of(w.tick))
	var dirty := state.dirty_cash
	Rackets.night(w, state)
	ok = _check(state.dirty_cash == dirty, "a robbed den takes nothing tonight") and ok
	# protection
	var plain := EmpireSystem.exposure(w, state, shops[0])
	var c: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_dealer or n.is_down) and n.gang_id == &"":
			c = n
			break
	c.is_crew = true
	c.crew_role = GanstoidEnums.CrewRole.MUSCLE
	c.position = shops[0].position + Vector2(20, 0)
	state.crew_ids.append(c.id)
	var crew := EmpireSystem.exposure(w, state, shops[0])
	state.fronts[&"x"] = "security"
	var both := EmpireSystem.exposure(w, state, shops[0])
	ok = _check(plain == 1.0 and is_equal_approx(crew, 0.5) and both < crew, "crew posted nearby halve the risk, a security firm cuts it more (%.2f -> %.2f -> %.2f)" % [plain, crew, both]) and ok
	if ok:
		print("EMPIRE_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("EMPIRE_VERIFY: FAIL - " + what)
	return good
