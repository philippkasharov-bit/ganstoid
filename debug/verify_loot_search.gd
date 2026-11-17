## LT4 validator: inside a place you broke into, every piece of furniture is
## its own container, shut until you search it; a search takes its time
## (a safe much longer than a sofa, less with theft skill), is broken off if
## you move, and then shows what's in it; a refill needs searching again;
## pockets of someone down are searched the same way; rich homes have a
## safe; the tables hold a wide spread of things; pawning pays clean, a
## fence pays more but dirty; you can deal hand to hand at your price, and
## the same person isn't asked twice in a day.
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
	var house: BuildingData = null
	var rich: BuildingData = null
	for e in w.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.building_type == GanstoidEnums.BuildingType.RESIDENCE and b.id != me.home_building_id:
			var wealth := float(BlockEconomyData.block_at(w, b.position).get("wealth", 0.0))
			if house == null and wealth < LootTables.SAFE_WEALTH:
				house = b
			if rich == null and wealth >= LootTables.SAFE_WEALTH:
				rich = b
	ok = _check(not LootTables.containers_for(house, w).has("safe") and LootTables.containers_for(rich, w).has("safe"), "a wall safe only in rich homes") and ok
	me.position = house.position
	state.inside_id = house.id
	var near := Vicinity.near(w, me, state)
	var shut := near.filter(func(s: Dictionary) -> bool: return s.get("unsearched", false))
	ok = _check(shut.size() == LootTables.HOME.size() and near.size() == shut.size(), "inside: %d pieces of furniture, all still shut" % shut.size()) and ok
	ok = _check(LootTables.search_secs("safe", 0) > LootTables.search_secs("sofa", 0) * 3.0 and LootTables.search_secs("drawers", 10) < LootTables.search_secs("drawers", 0), "a safe takes far longer than a sofa; theft skill speeds it up") and ok
	# search the drawers: interrupted, then done
	var drawers: Dictionary = shut.filter(func(s: Dictionary) -> bool: return s["cont"] == "drawers")[0]
	TimedAction.start_move(w, state, {"op": "search", "src": drawers, "secs": float(drawers["secs"])})
	w.tick += 30
	var r := TimedAction.advance(w, me, state, true)
	ok = _check(r.get("reason", "") == "interrupted" and not Containers.searched(me, house, "drawers"), "moving breaks the search off") and ok
	TimedAction.start_move(w, state, {"op": "search", "src": drawers, "secs": float(drawers["secs"])})
	var done := {}
	for i in 600:
		w.tick += 1
		done = TimedAction.advance(w, me, state, false)
		if not done.is_empty():
			break
	var inp := w.find_system(PlayerInputSystem) as PlayerInputSystem
	ok = _check(done.has("do_move") and not Containers.searched(me, house, "drawers"), "the bar fills, then the search lands") and ok
	inp._do_move(me, state, done["do_move"])
	ok = _check(Containers.searched(me, house, "drawers"), "after its time, the drawers are searched") and ok
	near = Vicinity.near(w, me, state)
	ok = _check(not near.any(func(s: Dictionary) -> bool: return s.get("unsearched", false) and s["cont"] == "drawers"), "and show what's in them (%s)" % str(house.containers["drawers"]["items"])) and ok
	# a refill needs searching again
	for id in (house.containers["drawers"]["items"] as Dictionary).keys():
		Containers.take(w, house, "drawers", id, 99)
	house.containers["drawers"]["items"] = {}
	house.containers["drawers"]["emptied_tick"] = w.tick
	w.tick += int(LootTables.RESTOCK_DAYS * SimClock.day_ticks) + 10
	house.cash_on_hand = 100000
	Containers.open(w, me, house)
	ok = _check(not Containers.searched(me, house, "drawers") or house.containers["drawers"]["items"].is_empty(), "restocked drawers have to be searched again") and ok
	# pockets
	var down: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not n.is_cop and not n.is_dealer:
			down = n
			break
	down.is_down = true
	down.position = me.position + Vector2(1, 0)
	w.reindex_position(down.id)
	state.inside_id = &""
	near = Vicinity.near(w, me, state)
	var pockets := near.filter(func(s: Dictionary) -> bool: return s["kind"] == "body")
	ok = _check(pockets.size() == 1 and pockets[0].get("unsearched", false), "someone down: their pockets need searching") and ok
	Vicinity.mark_searched(w, pockets[0])
	near = Vicinity.near(w, me, state)
	ok = _check(not near.any(func(s: Dictionary) -> bool: return s.get("unsearched", false)), "then show what they carry") and ok
	# variety
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for kind in LootTables.HOME + ["safe", "pockets", "stockroom"]:
		for i in 300:
			for id in LootTables.roll(kind, rng):
				seen[id] = true
	ok = _check(seen.size() >= 35, "%d different things turn up in homes, safes, pockets and stockrooms" % seen.size()) and ok
	# pawn and fence
	state.inventory = {&"watch": 2, &"vcr": 1}
	var worth := 2 * 150 + 120
	me.cash = 0
	state.dirty_cash = 0
	r = Fence.pawn(w, state)
	ok = _check(r["ok"] and me.cash == roundi(150 * 0.35) * 2 + roundi(120 * 0.35) and state.dirty_cash == 0, "pawned for $%d clean" % me.cash) and ok
	state.inventory = {&"watch": 2, &"vcr": 1}
	r = Fence.fence(w, state)
	ok = _check(r["ok"] and state.dirty_cash == roundi(150 * 0.5) * 2 + roundi(120 * 0.5), "fenced for $%d dirty (of $%d)" % [state.dirty_cash, worth]) and ok
	# dealing yourself
	state.inventory = {&"weed": 60}
	state.prices = {}
	state.dealt = {}
	var sold := 0
	var asked := 0
	var first: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n == me or n.is_cop or n.is_crew or n.is_dealer or n.is_down or asked >= 60:
			continue
		asked += 1
		if first == null:
			first = n
		if StreetDeal.sell(w, me, state, n, &"weed").get("ok", false):
			sold += 1
	ok = _check(sold >= 10 and sold < asked, "hand to hand at the going rate: %d of %d bought" % [sold, asked]) and ok
	ok = _check(StreetDeal.sell(w, me, state, first, &"weed").get("reason", "") == "already_refused", "the same person isn't asked twice in a day") and ok
	state.dealt = {}
	state.prices = {&"weed": 500}
	var dear := 0
	var asked2 := 0
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n == me or n.is_cop or n.is_crew or n.is_dealer or n.is_down or asked2 >= 60:
			continue
		asked2 += 1
		if StreetDeal.sell(w, me, state, n, &"weed").get("ok", false):
			dear += 1
	ok = _check(dear * 3 < sold, "at $500 a bag almost nobody buys (%d of 60)" % dear) and ok
	if ok:
		print("LOOT_SEARCH_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("LOOT_SEARCH_VERIFY: FAIL - " + what)
	return good
