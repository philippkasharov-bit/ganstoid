## RP3 validator: a gang only takes you on its turf, when you're in good with
## it, known on the street and not hunted by its lieutenant; joining makes
## the other gangs hold a grudge; missions count from what you do and pay;
## gang rep raises your rank; a member gets a cut every morning; at the top
## the old lieutenant steps aside; leaving makes them your enemy.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var gl := w.find_system(GangLifeSystem) as GangLifeSystem
	var ok := true
	RivalSystem.ensure(w, state)
	var t := TerritorySystem.data(w)
	var gang := &""
	var spot := Vector2.ZERO
	for c in t.cells:
		var g := TerritorySystem.controller(t, c)
		if g != &"" and g != TerritorySystem.PLAYER and Hoods.is_block(c) and TerritoryData.turf_of(TerritoryData.centre_of(c)) == c:
			gang = g
			spot = TerritoryData.centre_of(c)
			break
	me.position = spot
	w.reindex_position(me.id)
	ok = _check(GangLifeSystem.join(w, state, gang).get("reason", "") == "gang_standing", "strangers aren't taken") and ok
	state.gang_standing[gang] = 0.7
	ok = _check(GangLifeSystem.join(w, state, gang).get("reason", "") == "gang_unknown", "nobodies aren't taken") and ok
	state.fame = 15.0
	state.rivals[gang]["grudge"] = 40.0
	ok = _check(GangLifeSystem.join(w, state, gang).get("reason", "") == "gang_grudge", "not if their lieutenant is after you") and ok
	state.rivals[gang]["grudge"] = 0.0
	var other: StringName = state.rivals.keys().filter(func(g: StringName) -> bool: return g != gang)[0]
	var before := float(state.rivals[other]["grudge"])
	ok = _check(GangLifeSystem.join(w, state, gang).get("ok", false) and state.gang_member == gang, "a known friend on their turf is jumped in") and ok
	ok = _check(float(state.rivals[other]["grudge"]) > before, "the other gangs hold it against you") and ok
	gl._morning(state, 5)
	print("missions: ", state.gang_missions.map(func(m: Dictionary) -> String: return GangLifeSystem.mission_text(m)))
	ok = _check(state.gang_missions.size() == GangLifeSystem.PER_DAY, "two missions a day") and ok
	state.gang_missions = [{"kind": "sell", "got": 0, "need": 3, "done": false}]
	var cash := me.cash
	for i in 3:
		StreetTalk.say(w, state, {"ok": true, "effect": "sell", "proceeds": 30})
	ok = _check(state.gang_missions[0]["done"] and state.gang_rep > 0 and me.cash > cash, "a mission counts from what you do and pays") and ok
	state.gang_rep = GangLifeSystem.RANK_AT[1] - 1
	state.gang_missions = [{"kind": "tax", "got": 0, "need": 1, "done": false}]
	GangLifeSystem.progress(w, state, "tax")
	ok = _check(state.gang_rank == 1, "gang rep raises your rank") and ok
	var g_data: GangData = w.entities[gang].get_component(ComponentNames.GANG)
	g_data.cash = 10000
	cash = me.cash
	gl._morning(state, 6)
	ok = _check(me.cash > cash and g_data.cash < 10000, "a ranked member gets a cut every morning") and ok
	state.gang_rep = GangLifeSystem.RANK_AT[3] - 1
	state.gang_missions = [{"kind": "tax", "got": 0, "need": 1, "done": false}]
	GangLifeSystem.progress(w, state, "tax")
	ok = _check(state.gang_rank == 3 and not state.rivals.has(gang), "at Lieutenant the old one steps aside") and ok
	ok = _check(GangLifeSystem.leave(w, state).get("ok", false) and state.gang_member == &"" and float(state.rivals.get(gang, {}).get("grudge", 0.0)) >= GangLifeSystem.LEAVE_GRUDGE * 0.6, "leaving makes them your enemy") and ok
	if ok:
		print("JOIN_GANG_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("JOIN_GANG_VERIFY: FAIL - ", what)
	return good
