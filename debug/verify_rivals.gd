## RV1 validator: every gang gets a named lieutenant (the same after a
## reload); hurting his people grows his grudge; at THREAT you hear about
## it, at HUNT he sends people when you are near his turf; knocked out he
## comes back scarred with a new name and a worse grudge; killed, a new
## lieutenant (one level up) takes over; both make the paper.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var rs := w.find_system(RivalSystem) as RivalSystem
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var ok := true
	RivalSystem.ensure(w, state)
	var first := state.rivals.duplicate(true)
	state.rivals = {}
	RivalSystem.ensure(w, state)
	print("rivals: ", state.rivals.values().map(func(r: Dictionary) -> String: return "%s (%s, %s)" % [r["name"], r["real"], r["temper"]]))
	ok = _check(state.rivals.size() >= 2 and state.rivals == first, "each gang has a named lieutenant, the same after a reload") and ok
	var g: StringName = state.rivals.keys()[0]
	var r: Dictionary = state.rivals[g]
	var member: NPCData = null
	for m in (w.entities[g].get_component(ComponentNames.GANG) as GangData).member_npc_ids:
		if m != r["npc"]:
			member = w.entities[m].get_component(ComponentNames.NPC)
			break
	for i in 4:
		rs.on_assaulted(GanstoidEvents.ASSAULTED, {"victim_id": member.id, "position": me.position, "tick": w.tick})
	var said := state.message_serial
	var t := SimClock.hours(30.0)
	t += RivalSystem.PHASE - t % RivalSystem.EVERY
	rs.process_entities(players, 0.0, t)
	print("grudge %.0f, stage %d: %s" % [r["grudge"], r["stage"], state.last_message])
	ok = _check(float(r["grudge"]) >= RivalSystem.THREAT and state.message_serial > said, "hurting his people grows the grudge and the word reaches you") and ok
	r["grudge"] = RivalSystem.HUNT + 5.0
	var tt := TerritorySystem.data(w)
	for c in tt.cells:
		if TerritorySystem.controller(tt, c) == g and Hoods.is_block(c):
			me.position = TerritoryData.centre_of(c)
			break
	w.reindex_position(me.id)
	var combat := w.find_system(NPCCombatSystem) as NPCCombatSystem
	rs.process_entities(players, 0.0, t + RivalSystem.EVERY)
	print("on his turf: %d of his people after you" % combat.hostile.size())
	ok = _check(combat.hostile.size() > 0, "near his turf at HUNT he sends people") and ok
	var lt: NPCData = w.entities[r["npc"]].get_component(ComponentNames.NPC)
	var old_name: String = r["name"]
	var grudge := float(r["grudge"])
	lt.is_down = true
	lt.ko_until_tick = t + 9999
	rs.process_entities(players, 0.0, t + RivalSystem.EVERY * 2)
	print("knocked out: %s -> %s, grudge %.0f" % [old_name, r["name"], r["grudge"]])
	ok = _check(r["name"] != old_name and int(r["scars"]) == 1 and float(r["grudge"]) > grudge, "knocked out he comes back scarred, renamed, angrier") and ok
	lt.ko_until_tick = -1   # now dead
	r["down_seen"] = false
	rs.process_entities(players, 0.0, t + RivalSystem.EVERY * 3)
	var nr: Dictionary = state.rivals.get(g, {})
	print("killed: new lieutenant %s, level %d, grudge %.0f" % [nr.get("name"), nr.get("level", 0), nr.get("grudge", 0.0)])
	ok = _check(not nr.is_empty() and int(nr["level"]) == 2 and nr["npc"] != lt.id, "killed, a new lieutenant one level up takes over") and ok
	var keys := state.news_today.map(func(n: Array) -> String: return n[0])
	ok = _check(keys.has("rival_scarred") and keys.has("rival_killed"), "both make the paper") and ok
	if ok:
		print("RIVALS_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("RIVALS_VERIFY: FAIL - ", what)
	return good
