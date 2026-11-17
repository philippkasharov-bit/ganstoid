## BZ6 validator: a shop you own becomes a front for clean money; a car wash
## washes far more; upgrades raise takings (x1.25 a step); rivals of the same
## trade nearby are counted; a restaurant does better on a rich block; the
## week's tax goes out of clean money; washing far more than you earn brings
## an audit (fine, washing frozen, on your file); a trucking company halves
## import stings, a security firm cuts raids and fights.
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
	var shop: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.daily_revenue > 0 and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			shop = b
			break
	shop.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	BuildingData.ownership_serial += 1
	me.cash = 30000
	state.dirty_cash = 0
	var wash := BusinessSystem.laundering_capacity(w)
	var r := FrontSystem.convert(w, state, shop, "car_wash")
	ok = _check(r["ok"] and state.fronts[shop.id] == "car_wash" and me.cash == 30000 - 2500, "a shop becomes a car wash for $2500 clean") and ok
	ok = _check(BusinessSystem.laundering_capacity(w) >= wash + shop.daily_revenue * 2, "a car wash washes far more (%d -> %d a day)" % [wash, BusinessSystem.laundering_capacity(w)]) and ok
	# upgrades and rivals
	var base := FrontSystem.takings_mult(w, state, shop)
	FrontSystem.upgrade(w, state, shop)
	FrontSystem.upgrade(w, state, shop)
	ok = _check(is_equal_approx(FrontSystem.takings_mult(w, state, shop), base * 1.5), "two upgrades: takings x1.5") and ok
	var crowded: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.daily_revenue > 0 and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and FrontSystem.rivals(w, b) >= 2:
			crowded = b
			break
	ok = _check(crowded != null, "rivals of the same trade are counted (a %s has %d nearby; the city's money day already splits the customers)" % [crowded.trade, FrontSystem.rivals(w, crowded)]) and ok
	state.fronts[shop.id] = "restaurant"
	var poor := 0.0
	var rich := 0.0
	var econ := BlockEconomyData.of(w)
	var cell := TerritoryData.cell_of(shop.position)
	var keep: Dictionary = econ.blocks.get(cell, {}).duplicate()
	econ.blocks[cell] = {"wealth": 0.1, "budget": 0, "police": 0.5, "black": 0.5}
	poor = FrontSystem.takings_mult(w, state, shop)
	econ.blocks[cell] = {"wealth": 0.9, "budget": 0, "police": 0.5, "black": 0.5}
	rich = FrontSystem.takings_mult(w, state, shop)
	econ.blocks[cell] = keep
	ok = _check(rich > poor * 1.5, "a restaurant takes more on a rich block (x%.2f vs x%.2f)" % [rich, poor]) and ok
	state.fronts[shop.id] = "car_wash"
	# the books
	shop.cash_on_hand = 400
	state.books = {}
	var paid := BusinessSystem.collect_all(w)
	ok = _check(paid > 0 and int(state.books["earned"]) == paid, "takings go in the books ($%d)" % paid) and ok
	state.books = {"earned": 1000, "washed": 0}
	var clean := Wallet.clean(w)
	FrontSystem.week_end(w, state, 7)
	ok = _check(Wallet.clean(w) == clean - 150 and String(state.inbox[-1]["text"]).contains("$150"), "Sunday: 15% tax ($150)") and ok
	ok = _check(FrontSystem.audit_chance(PlayerStateData.new()) == 0.0, "no washing, no audit risk") and ok
	state.case_evidence = 0.0
	var audited := false
	for i in 30:
		state.books = {"earned": 100, "washed": 5000}
		FrontSystem.week_end(w, state, 14 + 7 * i)
		if state.stamp.get("text", "") == "AUDITED":
			audited = true
			break
	w.tick = SimClock.day_ticks * 15
	ok = _check(audited and state.case_evidence >= FrontSystem.AUDIT_CASE, "washing $5000 on $100 of takings brings the IRS") and ok
	state.books["frozen_until"] = HustleSystem.day_of(w.tick) + 2
	ok = _check(FrontSystem.frozen(w, state) and BusinessSystem.laundering_capacity(w) == 0, "after an audit, no washing for a while") and ok
	state.books["frozen_until"] = -1
	# trucks and guards
	ok = _check(FrontSystem.sting_mult(state) == 1.0 and FrontSystem.guard_mult(state) == 1.0, "no perks without the firms") and ok
	state.fronts[&"x1"] = "trucking"
	state.fronts[&"x2"] = "security"
	ok = _check(FrontSystem.sting_mult(state) == 0.5 and FrontSystem.guard_mult(state) < 1.0, "trucking halves import stings; security cuts raids and fights") and ok
	if ok:
		print("FRONTS_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("FRONTS_VERIFY: FAIL - " + what)
	return good
