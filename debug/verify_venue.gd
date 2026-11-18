## BZ3 validator: a shop you own becomes a night spot for a licence in clean
## money (and stops paying as a shop); fit-out and a good manager add stars;
## each night pays at closing, more with stars; without a bouncer some
## nights end in a fight, with one none do; a back room makes dirty money
## until vice raids it (case, paper, stamp, shut); night spots wash more
## dirty money. At the table: back-room games only at night at a pawn shop
## or liquor store; blackjack totals; every bet and payout adds up in your
## cash; walking away ends the game.
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
		if b.daily_revenue > 0 and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and not StaffSystem.candidates(w, state, b.position).is_empty():
			shop = b
			break
	shop.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	BuildingData.ownership_serial += 1
	var wash_before := BusinessSystem.laundering_capacity(w)
	me.cash = 100
	state.dirty_cash = 0
	ok = _check(VenueSystem.convert(w, state, shop.id, "club").get("reason", "") == "need_clean_cash", "a licence needs clean money") and ok
	me.cash = 20000
	var r := VenueSystem.convert(w, state, shop.id, "club")
	ok = _check(r["ok"] and state.venues.has(shop.id) and me.cash == 18000, "a nightclub for a $2000 licence") and ok
	shop.cash_on_hand = 500
	ok = _check(BusinessSystem.collect_all(w) == 0, "it no longer pays as a shop") and ok
	ok = _check(VenueSystem.stars(state, shop.id) == 1, "a bare room: one star") and ok
	VenueSystem.decorate(w, state, shop.id)
	var cands := StaffSystem.candidates(w, state, shop.position)
	StaffSystem.hire(w, state, cands[0], shop.id, "manager")
	state.staff[cands[0]]["skill"] = 0.8
	state.staff[cands[0]]["honesty"] = 1.0
	ok = _check(VenueSystem.stars(state, shop.id) == 3, "fitted out with a good manager: three stars") and ok
	# nights
	var fights := 0
	var takings := 0
	for i in 40:
		var c := me.cash
		VenueSystem.close_night(w, state)
		takings += me.cash - c
		fights += 1 if state.venues[shop.id]["fight"] else 0
	print("40 nights, three stars: $%d, %d fights" % [takings, fights])
	ok = _check(takings > 40 * 200 and fights > 0, "the nights pay; without a bouncer some end in a fight") and ok
	ok = _check(StaffSystem.hire(w, state, cands[1], shop.id, "bouncer")["ok"], "a bouncer on the door as well as a manager") and ok
	fights = 0
	for i in 40:
		VenueSystem.close_night(w, state)
		fights += 1 if state.venues[shop.id]["fight"] else 0
	ok = _check(fights == 0, "with a bouncer, no fights") and ok
	ok = _check(BusinessSystem.laundering_capacity(w) > wash_before, "a night spot washes dirty money (%d -> %d a day)" % [wash_before, BusinessSystem.laundering_capacity(w)]) and ok
	# the back room
	r = VenueSystem.open_back_room(w, state, shop.id)
	var dirty := state.dirty_cash
	state.case_evidence = 0.0
	var nights := 0
	for tries in 20:   # raided on its very first night (a fair roll) earns nothing: open it again and play on
		if tries > 0:
			Wallet.earn_clean(w, VenueSystem.BACK_ROOM_COST)
			VenueSystem.open_back_room(w, state, shop.id)
		while state.venues[shop.id]["back_room"] and nights < 500:
			VenueSystem.close_night(w, state)
			nights += 1
		if state.dirty_cash > dirty:
			break
	ok = _check(r["ok"] and state.dirty_cash > dirty, "the back room makes dirty money ($%d in %d nights)" % [state.dirty_cash - dirty, nights]) and ok
	ok = _check(not state.venues[shop.id]["back_room"] and state.case_evidence >= VenueSystem.RAID_CASE and state.stamp.get("text", "") == "RAIDED", "until vice raids it: shut, on your case") and ok
	ok = _check(state.news_today.any(func(n: Array) -> bool: return n[0] == "den_raided"), "the raid makes the paper") and ok
	# the table
	var pawn: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if GambleSystem.TRADES.has(b.trade) and b.status < 2:
			pawn = b
			break
	w.tick = SimClock.hours(36.0)
	ok = _check(not GambleSystem.game_at(w, state, pawn.id), "no game at noon") and ok
	w.tick = SimClock.hours(47.0)
	ok = _check(GambleSystem.game_at(w, state, pawn.id) and GambleSystem.sit(w, state, pawn.id)["ok"], "a back-room game at 11 pm (%s)" % pawn.trade) and ok
	ok = _check(GambleSystem.total([1, 13]) == 21 and GambleSystem.total([1, 1, 9]) == 21 and GambleSystem.total([10, 12, 5]) == 25, "blackjack counts aces and faces right") and ok
	me.position = pawn.position
	w.reindex_position(me.id)
	me.cash = 5000
	state.dirty_cash = 0
	var start := me.cash
	for i in 60:
		if i % 2 == 0:
			GambleSystem.play(w, me, state, {"op": "deal", "bet": 50})
			while state.gamble["stage"] == "play":
				GambleSystem.play(w, me, state, {"op": "hit" if GambleSystem.total(state.gamble["you"]) < 15 else "stand"})
		else:
			GambleSystem.play(w, me, state, {"op": "dice", "bet": 10})
	print("60 rounds: net $%d" % int(state.gamble["net"]))
	ok = _check(me.cash - start == int(state.gamble["net"]), "every bet and payout adds up (net $%d)" % int(state.gamble["net"])) and ok
	var sys := w.find_system(GambleSystem) as GambleSystem
	me.position = pawn.position + Vector2(30, 0)
	sys.process_entities({PlayerFactory.PLAYER_ENTITY_ID: p}, 0.0, w.tick)
	ok = _check(state.gamble.is_empty(), "walk away and the game ends") and ok
	if ok:
		print("VENUE_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("VENUE_VERIFY: FAIL - " + what)
	return good
