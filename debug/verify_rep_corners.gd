## RP1/CW1 validator. Reputation: the tier follows fame, a new tier gets a
## stamp, a higher tier makes recruits more willing. Corner war: taking a
## block is announced; a gang next to your block makes a push (within a few
## game days); ignore it and the gang takes a big bite; be on the block and
## beat two of them and the corner holds (and makes the paper).
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var ok := true
	state.fame = 5.0
	var someone: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_dealer or n.is_crew) and n.gang_id == &"":
			someone = n
			break
	var before := CrewSystem.willingness(w, someone)
	var stamps := state.stamp_serial
	Rep.add(state, 30.0)
	print("rep: %s (%.0f), recruit willingness %.2f -> %.2f" % [Rep.name_of(state), state.fame, before, CrewSystem.willingness(w, someone)])
	ok = _check(Rep.name_of(state) == "Respected" and state.stamp_serial > stamps and CrewSystem.willingness(w, someone) > before, "reputation tiers, a stamp, and more willing recruits") and ok

	var cw := w.find_system(CornerWarSystem) as CornerWarSystem
	var t := TerritorySystem.data(w)
	var mine := Vector2i(-1, -1)
	var gang := &""
	for c in t.cells:
		var g := TerritorySystem.controller(t, c)
		if g == &"" or g == TerritorySystem.PLAYER or not Hoods.is_block(c):
			continue
		for n in TerritoryData.neighbours(c):
			if Hoods.is_block(n) and TerritorySystem.controller(t, n) == &"":
				mine = n
				gang = g
				break
		if gang != &"":
			break
	var tick := SimClock.hours(24.0 + 12.0)
	tick += CornerWarSystem.PHASE - tick % CornerWarSystem.EVERY
	cw.process_entities(players, 0.0, tick)   # first look
	TerritorySystem.set_influence(t, mine, TerritorySystem.PLAYER, 90.0)
	var inbox := state.inbox.size()
	cw.process_entities(players, 0.0, tick + CornerWarSystem.EVERY)
	print("took %s: %s" % [CornerWarSystem.block_name(mine), state.inbox[-1]["text"] if state.inbox.size() > inbox else "-"])
	ok = _check(state.inbox.size() > inbox and String(state.inbox[-1]["text"]).ends_with("is ours now."), "taking a block is announced") and ok

	var days := 0
	while state.turf_push.is_empty() and days < 30:
		days += 1
		cw.process_entities(players, 0.0, tick + SimClock.hours(24.0 * days) + CornerWarSystem.EVERY * 2)
	print("a push after %d days: %s" % [days, state.inbox[-1]["text"]])
	ok = _check(not state.turf_push.is_empty(), "a gang next to your block makes a push") and ok
	var c: Vector2i = state.turf_push["cell"]
	var g: StringName = state.turf_push["gang"]
	var inf := TerritorySystem.get_influence(t, c, g)
	me.position = TerritoryData.centre_of(c) + Vector2(400, 0)
	var mine_before := TerritorySystem.get_influence(t, c, TerritorySystem.PLAYER)
	cw._run_push(t, state, me, int(state.turf_push["until"]) + 1)
	ok = _check(state.turf_push.is_empty() and TerritorySystem.get_influence(t, c, TerritorySystem.PLAYER) < mine_before, "ignored, the gang takes a bite") and ok

	state.turf_push = {"cell": c, "gang": g, "until": tick + SimClock.hours(400.0), "sent": false, "ko": 0, "seen_down": []}
	me.position = TerritoryData.centre_of(c)
	w.reindex_position(me.id)
	var mine_inf := TerritorySystem.get_influence(t, c, TerritorySystem.PLAYER)
	cw._run_push(t, state, me, tick + 10)
	var squad: Array = state.turf_push.get("squad", [])
	print("on the block: %d of them came" % squad.size())
	for id in squad.slice(0, 2):
		(w.entities[id].get_component(ComponentNames.NPC) as NPCData).is_down = true
	cw._run_push(t, state, me, tick + 20)
	ok = _check(squad.size() > 0 and state.turf_push.is_empty() and TerritorySystem.get_influence(t, c, TerritorySystem.PLAYER) > mine_inf, "beat two of them on the block and the corner holds") and ok
	ok = _check(state.news_today.map(func(n: Array) -> String: return n[0]).has("corner_held"), "a held corner makes the paper") and ok
	if ok:
		print("REP_CORNERS_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("REP_CORNERS_VERIFY: FAIL - ", what)
	return good
