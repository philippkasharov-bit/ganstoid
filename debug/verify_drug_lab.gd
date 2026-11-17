## BZ4 validator: street drugs are two stars (old prices); the press turns
## powder into pills; a cook kept in the green makes top meth, one left
## alone catches fire (burn, case, stamp); imports need Soldier rank, take
## cash up front, wait at a warehouse in a window, and are sometimes a
## sting; a missed window loses the load; coke can be stepped on; stars
## average as you buy; your clubs' door staff sell your pills by night.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	w.tick = SimClock.hours(30.0)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var lab := w.find_system(DrugLabSystem) as DrugLabSystem
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var ok := true
	ok = _check(DrugLabSystem.stars(state, &"coke") == 2.0 and is_equal_approx(DrugLabSystem.price_mult(state, &"coke"), 1.0), "street coke: two stars, the old price") and ok
	state.inventory[&"pill_press"] = 1
	state.inventory[&"lab_glass"] = 1
	DrugLabSystem.install(w, state)
	state.inventory[&"pill_powder"] = 4
	var r := DrugLabSystem.press(w, state)
	ok = _check(r["ok"] and int(state.inventory[&"pills"]) == 12 and not state.inventory.has(&"pill_press"), "the press: 4 powder, 12 pills %s" % GrowSystem.stars_text(DrugLabSystem.stars(state, &"pills"))) and ok
	# a careful cook
	state.inventory[&"cold_meds"] = 5
	DrugLabSystem.start_cook(w, state)
	while not state.cook.is_empty():
		if float(state.cook["heat"]) > 0.68:
			DrugLabSystem.nudge(state, -1.0)
		elif float(state.cook["heat"]) < 0.58:
			DrugLabSystem.nudge(state, 1.0)
		DrugLabSystem.cook_step(w, me, state, 1.0 / 60.0)
	ok = _check(int(state.inventory.get(&"meth", 0)) == 10 and DrugLabSystem.stars(state, &"meth") >= 4.5, "a careful cook: 10 bags %s" % GrowSystem.stars_text(DrugLabSystem.stars(state, &"meth"))) and ok
	# a cook left alone
	state.inventory[&"cold_meds"] = 5
	DrugLabSystem.start_cook(w, state)
	var health := me.health
	state.case_evidence = 0.0
	while not state.cook.is_empty():
		DrugLabSystem.cook_step(w, me, state, 1.0 / 60.0)
	ok = _check(int(state.lab["fires"]) == 1 and me.health < health and state.case_evidence > 0.0 and state.stamp.get("text", "") == "FIRE!" and int(state.inventory[&"meth"]) == 10, "left alone it catches fire: burned, seen, batch gone") and ok
	# imports
	me.cash = 5000
	ok = _check(DrugLabSystem.order(w, me, state, &"coke").get("reason", "") == "lab_no_connect", "no connect for a Street rat") and ok
	state.rank = 2
	r = DrugLabSystem.order(w, me, state, &"coke")
	var at: StringName = state.shipment.get("at", &"")
	ok = _check(r["ok"] and me.cash == 3700 and at != &"" and state.waypoint != Vector2.INF, "a Soldier orders 20 coke for $1300; the GPS points at the warehouse") and ok
	ok = _check(not DrugLabSystem.can_pick_up(w, state, at), "not there yet") and ok
	w.tick = int(state.shipment["from"]) + 10
	state.shipment["sting"] = false
	ok = _check(DrugLabSystem.can_pick_up(w, state, at) and DrugLabSystem.pick_up(w, me, state)["ok"] and int(state.inventory[&"coke"]) == 20 and DrugLabSystem.stars(state, &"coke") == 4.0, "picked up in the window: 20 coke at four stars") and ok
	DrugLabSystem.order(w, me, state, &"heroin")
	w.tick = int(state.shipment["from"]) + 10
	state.shipment["sting"] = true
	state.case_evidence = 0.0
	r = DrugLabSystem.pick_up(w, me, state)
	ok = _check(not r["ok"] and state.case_evidence >= DrugLabSystem.STING_CASE and not state.inventory.has(&"heroin") and state.stamp.get("text", "") == "STING!", "a sting: nothing, and a bigger case") and ok
	DrugLabSystem.order(w, me, state, &"heroin")
	var inbox := state.inbox.size()
	var t: int = int(state.shipment["until"]) + 60
	t += posmod(17 - t, 60)
	lab.process_entities(players, 0.0, t)
	ok = _check(state.shipment.is_empty() and state.inbox.size() > inbox, "miss the window and the load is gone") and ok
	# stepping on it, and buying averages
	DrugLabSystem.cut(w, state, &"coke")
	ok = _check(int(state.inventory[&"coke"]) == 30 and DrugLabSystem.stars(state, &"coke") == 3.0, "stepped on: 20 -> 30 coke, three stars") and ok
	DrugLabSystem.add_drug(state, &"coke", 30, 2.0)
	ok = _check(is_equal_approx(DrugLabSystem.stars(state, &"coke"), 2.5), "buying street coke on top averages the stars (2.5)") and ok
	# pills at your club
	var shop: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.daily_revenue > 0 and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			shop = b
			break
	shop.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	state.venues[shop.id] = {"kind": "club", "decor": 2, "back_room": false, "last": 0}
	VenueSystem.stock_pills(w, state, shop.id)
	ok = _check(not state.inventory.has(&"pills") and int(state.venues[shop.id]["pills"]) == 12, "12 pills left with the door staff") and ok
	var dirty := state.dirty_cash
	for i in 10:
		if int(state.venues[shop.id].get("pills", 0)) == 0:
			state.venues[shop.id]["pills"] = 12   # vice found them: stock up again
		VenueSystem.close_night(w, state)
		if int(state.venues[shop.id].get("sold", 0)) > 0:
			break
	ok = _check(state.dirty_cash > dirty and int(state.venues[shop.id].get("sold", 0)) > 0, "the door staff sell them by night ($%d dirty)" % (state.dirty_cash - dirty)) and ok
	if ok:
		print("DRUG_LAB_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("DRUG_LAB_VERIFY: FAIL - " + what)
	return good
