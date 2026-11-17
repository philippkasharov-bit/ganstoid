## BZ5b validator: a pawn shop you own runs a stolen-goods ring that earns
## dirty money every night until the police shut it (case, stamp), and buys
## your own loot at 70%; a flat you own becomes a gambling den that earns
## by night and stops paying rent; the connect sells a crate of six pistols.
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
	# the ring
	var pawn: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.trade == &"pawn shop":
			pawn = b
			break
	me.cash = 10000
	state.dirty_cash = 0
	ok = _check(Rackets.open_ring(w, state, pawn).get("reason", "") == "venue_cant", "only a pawn shop you own can run a ring") and ok
	pawn.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	BuildingData.ownership_serial += 1
	var r := Rackets.open_ring(w, state, pawn)
	ok = _check(r["ok"] and Rackets.ring_at(state, pawn.id) and me.cash == 10000 - Rackets.RING_COST, "a ring opens for $%d" % Rackets.RING_COST) and ok
	var nights := 0
	state.case_evidence = 0.0
	while Rackets.ring_at(state, pawn.id) and nights < 400:
		Rackets.night(w, state)
		nights += 1
	ok = _check(state.dirty_cash > 0 and not Rackets.ring_at(state, pawn.id) and state.case_evidence >= Rackets.RAID_CASE and state.stamp.get("text", "") == "RAIDED", "it earns ($%d dirty in %d nights) until the police shut it" % [state.dirty_cash, nights]) and ok
	ok = _check(is_equal_approx(TradeSystem.share_of("ring"), 0.7) and TradeSystem.share_of("pawn") < TradeSystem.share_of("ring"), "your ring pays 70% for your own loot, more than a pawn shop") and ok
	# the den
	var flat: BuildingData = null
	for e in w.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.building_type == GanstoidEnums.BuildingType.RESIDENCE and b.id != me.home_building_id:
			flat = b
			break
	state.properties = [flat.id]
	state.property_prices = {flat.id: 6000}
	var gig := w.find_system(GigSystem) as GigSystem
	var c := me.cash
	gig._rent(state)
	var rent := me.cash - c
	r = Rackets.open_den(w, state, flat.id)
	ok = _check(rent > 0 and r["ok"] and Rackets.den_at(state, flat.id), "a flat paying $%d rent becomes a gambling den" % rent) and ok
	c = me.cash
	gig._rent(state)
	ok = _check(me.cash == c, "a den pays no rent") and ok
	var dirty := state.dirty_cash
	for i in 5:
		if Rackets.den_at(state, flat.id):
			Rackets.night(w, state)
	ok = _check(state.dirty_cash > dirty, "the den pays by night ($%d)" % (state.dirty_cash - dirty)) and ok
	ok = _check(Rackets.open_den(w, state, me.home_building_id).get("reason", "") == "venue_cant", "not in your own home") and ok
	# guns
	state.rank = 2
	me.cash = 5000
	r = DrugLabSystem.order(w, me, state, &"guns")
	w.tick = int(state.shipment["from"]) + 10
	state.shipment["sting"] = false
	var guns := int(state.inventory.get(&"pistol", 0))
	DrugLabSystem.pick_up(w, me, state)
	ok = _check(r["ok"] and me.cash == 3200 and int(state.inventory.get(&"pistol", 0)) == guns + 6, "a crate of six pistols for $1800, to sell to the gangs") and ok
	if ok:
		print("RACKETS2_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("RACKETS2_VERIFY: FAIL - " + what)
	return good
