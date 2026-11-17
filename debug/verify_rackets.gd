## BZ5 validator: people nearby ask to borrow; a loan goes out of your cash
## and comes back with interest day by day; a bad payer goes late; you can
## collect what they carry, lean on them (they pay double) or make an
## example (written off, the others pay up, fame, a crime). Fake money:
## the press prints graded bills; a good bill passes for real change, two a
## shop a day; a bad one gets spotted (store shuts you out, police called);
## dealers buy them. The chop shop pays for a stolen car parked outside and
## the car is gone.
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
	# asks
	var day := 2
	for i in 20:
		LoanSystem.new_day(w, me, state, day)
		if not state.loan_asks.is_empty():
			break
	ok = _check(state.loan_asks.size() in [1, 2], "people near you ask to borrow (%s)" % str(state.loan_asks.map(func(a: Dictionary) -> String: return "$%d at %d%%" % [a["amount"], roundi(a["rate"] * 100)]))) and ok
	me.cash = 5000
	state.dirty_cash = 0
	var a: Dictionary = state.loan_asks[0]
	var r := LoanSystem.lend(w, me, state, 0)
	var loan: Dictionary = state.loans[0]
	ok = _check(r["ok"] and me.cash == 5000 - int(a["amount"]) and int(loan["owed"]) == roundi(int(a["amount"]) * (1.0 + float(a["rate"]))), "a loan of $%d goes out; $%d owed" % [int(a["amount"]), int(loan["owed"])]) and ok
	loan["fear"] = 1.0   # a sure payer, for the repayment test
	for i in LoanSystem.TERM_DAYS + 1:
		day += 1
		LoanSystem.new_day(w, me, state, day)
	ok = _check(int(loan["owed"]) == 0 and state.dirty_cash == int(loan["total"]) and loan["status"] == "paid off", "paid back day by day, with interest ($%d dirty)" % state.dirty_cash) and ok
	# a bad payer
	var bad: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_down) and n.gang_id == &"" and LoanSystem.reliability(n.id) < 0.02:
			bad = n
			break
	state.loan_asks = [{"who": bad.id, "amount": 200, "rate": 0.3}]
	LoanSystem.lend(w, me, state, 0)
	var debt: Dictionary = LoanSystem.loan_of(state, bad.id)
	for i in LoanSystem.TERM_DAYS + 1:
		day += 1
		LoanSystem.new_day(w, me, state, day)
	ok = _check(debt["status"] == "late", "a bad payer goes late (%s, owes $%d)" % [debt["status"], int(debt["owed"])]) and ok
	bad.cash = 50
	var owed := int(debt["owed"])
	LoanSystem.collect(w, state, bad)
	ok = _check(int(debt["owed"]) == owed - 50 and bad.cash == 0, "collect what they carry ($50)") and ok
	LoanSystem.lean_on(w, me, state, bad)
	owed = int(debt["owed"])
	day += 1
	LoanSystem.new_day(w, me, state, day)
	ok = _check(debt.get("scared", false) and int(debt["owed"]) <= owed - ceili(float(debt["total"]) / LoanSystem.TERM_DAYS) * 2 or int(debt["owed"]) == 0, "leaned on, they pay double") and ok
	# make an example
	state.loan_asks = [{"who": _someone(w, me, [bad.id]), "amount": 100, "rate": 0.2}]
	LoanSystem.lend(w, me, state, 0)
	var other: Dictionary = state.loans[-1]
	var fame := state.fame
	LoanSystem.make_example(w, me, state, bad)
	ok = _check(int(debt["owed"]) == 0 and float(other.get("fear", 0.0)) >= LoanSystem.EXAMPLE_FEAR and state.fame > fame and bad.health < 1.0, "an example: written off, the others scared into paying, your name grows") and ok
	# fake money
	state.lab["printer"] = true
	state.inventory[&"ink_paper"] = 2
	r = Rackets.print_money(w, state)
	ok = _check(r["ok"] and int(state.inventory[&"fake_bill"]) == 10, "the press prints 10 bills: %s" % Grades.drug_text(&"fake_bill", DrugLabSystem.stars(state, &"fake_bill"))) and ok
	var shop: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.status < 2:
			shop = b
			break
	state.products[&"fake_bill"] = 5.0
	me.cash = 0
	state.dirty_cash = 0
	var passed := 0
	for i in 3:
		if Rackets.pass_bill(w, me, state, shop.id).get("ok", false):
			passed += 1
	ok = _check(passed >= 1 and me.cash == passed * Rackets.CHANGE and state.dirty_cash == 0, "good bills pass for real change ($%d clean)" % me.cash) and ok
	ok = _check(Rackets.pass_bill(w, me, state, shop.id).get("reason", "") == "fake_too_many", "but not more than twice a shop a day") and ok
	state.products[&"fake_bill"] = 1.0
	state.inventory[&"fake_bill"] = 30
	state.case_evidence = 0.0
	var spotted := 0
	for i in 15:
		w.tick += SimClock.day_ticks
		if Rackets.pass_bill(w, me, state, shop.id).get("reason", "") == "fake_spotted":
			spotted += 1
	ok = _check(spotted >= 3 and state.case_evidence > 0.0 and MemorySystem.refuses(state, shop.id), "bad bills get spotted (%d of 15): the store shuts you out, the police get a call" % spotted) and ok
	var dirty := state.dirty_cash
	r = Rackets.sell_fakes(w, state)
	ok = _check(r["ok"] and state.dirty_cash > dirty and not state.inventory.has(&"fake_bill"), "a dealer buys the rest ($%d dirty)" % (state.dirty_cash - dirty)) and ok
	# chop shop
	var chop: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.trade == &"chop shop":
			chop = b
			break
	var car: VehicleData = null
	for e in w.get_entities_with_component(ComponentNames.VEHICLE).values():
		var c: VehicleData = e.get_component(ComponentNames.VEHICLE)
		if c.owner_id != PlayerFactory.PLAYER_ENTITY_ID:
			car = c
			break
	car.touched = true
	car.damage = 0.2
	car.position = chop.position + Vector2(6, 0)
	w.reindex_position(car.id)
	state.vehicle_id = car.id
	car.driver_id = PlayerFactory.PLAYER_ENTITY_ID
	var price := Rackets.chop_price(car)
	dirty = state.dirty_cash
	r = Rackets.chop(w, state, chop)
	ok = _check(r["ok"] and state.dirty_cash == dirty + price and state.vehicle_id == &"" and car.position.x < -10000.0, "the chop shop pays $%d and the car is gone" % price) and ok
	if ok:
		print("RACKETS_VERIFY: PASS")
	quit(0 if ok else 1)

func _someone(w: World, me: NPCData, not_ids: Array) -> StringName:
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_down) and not not_ids.has(n.id):
			return n.id
	return &""

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("RACKETS_VERIFY: FAIL - " + what)
	return good
