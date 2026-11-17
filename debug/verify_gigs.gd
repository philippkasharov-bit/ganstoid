## RP2 validator: three legal gigs a morning; a delivery is picked up and
## dropped off for clean pay; a taxi fare needs a car and a licence; a
## licence costs money; driving without one where a cop sees you goes on your
## case; homes for sale near you are bought with clean money only, can be
## moved into, and the others pay rent every morning.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	GameRules.install(w, 1, 1)   # Normal / Street life, as a new game
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var gs := w.find_system(GigSystem) as GigSystem
	var ok := true
	var t := SimClock.hours(32.0)
	GigSystem.roll(w, state, me, 1)
	print("gigs: ", state.gigs.map(func(g: Dictionary) -> String: return "%s $%d" % [g["kind"], g["pay"]]))
	ok = _check(state.gigs.size() == 3, "three gigs a morning") and ok
	var taxi := state.gigs.map(func(g: Dictionary) -> String: return g["kind"]).find("taxi")
	ok = _check(GigSystem.take(w, state, taxi, t).get("reason", "") == "gig_need_car", "a taxi fare needs a car and a licence") and ok
	var del := state.gigs.map(func(g: Dictionary) -> String: return g["kind"]).find("delivery")
	var pay := int(state.gigs[del]["pay"])
	ok = _check(GigSystem.take(w, state, del, t).get("ok", false) and state.waypoint == state.gig["from"], "taking a delivery sets the GPS to the pickup") and ok
	var clean := me.cash - state.dirty_cash
	me.position = state.gig["from"]
	GigSystem.advance(w, state, me, t)
	ok = _check(state.gig["stage"] == "dropoff" and state.waypoint == state.gig["to"], "picked up: the GPS points at the address") and ok
	me.position = state.gig["to"]
	GigSystem.advance(w, state, me, t)
	print("delivery: stage %s, clean $%d -> $%d (pay $%d)" % [state.gig.get("stage", "done"), clean, me.cash - state.dirty_cash, pay])
	ok = _check(state.gig.is_empty() and me.cash - state.dirty_cash >= clean + pay, "dropped off: clean pay (x the play style bonus)") and ok
	me.cash = 100
	ok = _check(GigSystem.buy_licence(w, state).get("reason", "") == "cant_afford", "a licence costs money") and ok
	me.cash = 1000
	ok = _check(GigSystem.buy_licence(w, state).get("ok", false) and state.licence and me.cash == 1000 - GigSystem.LICENCE_COST, "a licence bought") and ok
	state.licence = false
	state.vehicle_id = &"car_test"
	var cop: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.is_cop:
			cop = n
			break
	cop.position = me.position + Vector2(3, 0)
	w.reindex_position(cop.id)
	w.tick = SimClock.hours(36.0)
	var ev := state.case_evidence
	gs._licence_check(state, me, w.tick)
	ok = _check(state.case_evidence > ev, "driving without a licence in front of a cop goes on your case") and ok
	state.vehicle_id = &""
	var list := GigSystem.listings(w, state, me)
	print("for sale: ", list.map(func(l: Array) -> String: return "$%d" % l[1]))
	ok = _check(list.size() > 0, "homes for sale near you") and ok
	var id: StringName = list[0][0]
	var cost: int = list[0][1]
	me.cash = cost + 500
	state.dirty_cash = 600
	ok = _check(GigSystem.buy_property(w, state, id).get("reason", "") == "need_clean_cash", "dirty money doesn't buy a home") and ok
	me.cash = cost + 100
	state.dirty_cash = 0
	ok = _check(GigSystem.buy_property(w, state, id).get("ok", false) and state.properties.has(id), "bought with clean money") and ok
	var before := me.cash
	gs._rent(state)
	ok = _check(me.cash > before, "a home you don't live in pays rent") and ok
	ok = _check(GigSystem.move_in(w, state, me, id).get("ok", false) and me.home_building_id == id, "you can move in") and ok
	if ok:
		print("GIGS_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("GIGS_VERIFY: FAIL - ", what)
	return good
