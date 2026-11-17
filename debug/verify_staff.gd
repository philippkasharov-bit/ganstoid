## BZ2 validator: you can hire a grower from the people near home; leave
## them seeds and food and they plant, water, feed, harvest and bag into the
## stash on their own for days (a shifty one keeps a cut); a skilled one
## grows better weed; a manager lifts a shop's takings; wages go out each
## morning; a grower who goes unpaid quits angry and becomes a witness; let
## go with severance they go quietly; the same person always reads the same.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	w.tick = SimClock.hours(32.0)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	state.grow = {"tents": 1, "lamp": 2, "fan": true, "filter": true, "plants": [], "drying": []}
	var home: BuildingData = w.entities[me.home_building_id].get_component(ComponentNames.BUILDING)
	var cands := StaffSystem.candidates(w, state, home.position)
	ok = _check(cands.size() == StaffSystem.CANDIDATES, "%d people near home would take the job" % cands.size()) and ok
	var g: StringName = cands[0]
	var r := StaffSystem.request(w, me, state, {"hire": g, "at": &"grow", "role": "grower"})
	ok = _check(r["ok"] and state.staff.has(g) and int(state.staff[g]["wage"]) == StaffSystem.wage_of(StaffSystem.traits_of(g).x), "hired a grower at $%d a day" % int(state.staff[g]["wage"])) and ok
	ok = _check(not StaffSystem.hire(w, state, cands[1], &"grow", "grower")["ok"], "one grower per grow") and ok
	state.staff[g]["honesty"] = 0.3   # shifty: keeps a cut
	state.inventory[&"seeds_kush"] = 8
	state.inventory[&"plant_food"] = 10
	GrowSystem.stock_up(w, state)
	ok = _check(not state.inventory.has(&"seeds_kush") and int(state.grow["stock"][&"seeds_kush"]) == 8, "seeds and food left for the grower") and ok
	for i in int(24 * 3.5):
		w.tick += SimClock.hours(1.0)
		GrowSystem.tend_hour(w, me, state, w.tick)
	var stash := int(state.grow.get("stash", {}).get("units", 0))
	var kept := int(state.staff[g]["skimmed"])
	var dead := (state.grow["plants"] as Array).filter(func(pl: Dictionary) -> bool: return pl.get("dead", false)).size()
	print("after 3.5 days alone: stash %d bags, the grower kept %d, plants %d (dead %d), stock %s" % [stash, kept, state.grow["plants"].size(), dead, state.grow["stock"]])
	ok = _check(stash > 0 and dead == 0 and state.grow["plants"].size() == 4, "the grower ran the grow for days: bags in the stash, nothing died, replanted") and ok
	ok = _check(kept > 0, "a shifty grower keeps a cut (%d)" % kept) and ok
	ok = _check(GrowSystem.need_line(w, state).contains("pick them up") or stash < 10, "the pager says the stash is waiting") and ok
	var weed := int(state.inventory.get(&"weed", 0))
	GrowSystem.pick_up(w, state)
	ok = _check(int(state.inventory.get(&"weed", 0)) == weed + stash and not state.grow.has("stash"), "pick up the stash at home") and ok
	var pl := {"strain": &"seeds_kush", "at": 0, "watered": w.tick, "fed": 0, "care": 1.0}
	state.staff[g]["skill"] = 0.0
	var low := GrowSystem.quality(state, pl)
	state.staff[g]["skill"] = 1.0
	ok = _check(GrowSystem.quality(state, pl) > low, "a skilled grower grows better weed (%.1f -> %.1f)" % [low, GrowSystem.quality(state, pl)]) and ok
	# a manager
	var shop: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.daily_revenue > 0 and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and not StaffSystem.candidates(w, state, b.position).is_empty():
			shop = b
			break
	shop.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	var m: StringName = StaffSystem.candidates(w, state, shop.position)[0]
	StaffSystem.hire(w, state, m, shop.id, "manager")
	state.staff[m]["skill"] = 1.0
	state.staff[m]["honesty"] = 1.0
	ok = _check(StaffSystem.managed(state, shop.id, 100) == 140, "a top, honest manager: +40% takings") and ok
	state.staff[m]["honesty"] = 0.2
	ok = _check(StaffSystem.managed(state, shop.id, 100) == 140 - 42, "a shifty one keeps some ($%d)" % (140 - StaffSystem.managed(state, shop.id, 100))) and ok
	shop.cash_on_hand = 200
	var paid := BusinessSystem.collect_all(w)
	ok = _check(paid > 0 and int(state.biz_day["shops"]) == paid, "shop takings recorded for the Business app ($%d)" % paid) and ok
	# wages
	me.cash = 1000
	var wages := int(state.staff[g]["wage"]) + int(state.staff[m]["wage"])
	StaffSystem.pay_day(w, me, state)
	ok = _check(me.cash == 1000 - wages and int(state.biz_day["wages"]) == wages, "wages go out in the morning ($%d)" % wages) and ok
	me.cash = 0
	StaffSystem.pay_day(w, me, state)
	ok = _check(state.staff.is_empty() and CourtSystem.witnesses(w, state).has(g) and not CourtSystem.witnesses(w, state).has(m), "unpaid, they quit; the grower knows about your grow and will testify") and ok
	# severance
	StaffSystem.hire(w, state, cands[2], &"grow", "grower")
	me.cash = 1000
	var sev := int(state.staff[cands[2]]["wage"]) * StaffSystem.FIRE_DAYS
	r = StaffSystem.fire(w, me, state, cands[2])
	ok = _check(r["effect"] == "staff_fired" and me.cash == 1000 - sev and not state.memories.has(cands[2]), "let go with $%d they go quietly" % sev) and ok
	ok = _check(StaffSystem.traits_of(g) == StaffSystem.traits_of(g) and StaffSystem.traits_of(g) != StaffSystem.traits_of(m), "the same person always reads the same") and ok
	if ok:
		print("STAFF_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("STAFF_VERIFY: FAIL - " + what)
	return good
