## PP1/RX1 validator. Pickpocket: staying right behind a walking mark fills
## the lift and takes their cash; standing in front of them gets you caught.
## Reactions: a gun up makes people who see it run and the one at the barrel
## freeze; people run from a body; a gang on its own block warns you once and
## comes for you if you stay with a gun out (a plain passer-by is only warned).
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var city := TestWorlds.city()
	SimNav.install(city, city.spawn, 250.0)
	await TestWorlds.wait_nav(self, [SimNav.active])
	w.tick = SimClock.hours(36.0)   # midday
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var sched := w.find_system(NPCScheduleSystem) as NPCScheduleSystem
	var ok := true

	# a lift from behind
	var mark := _someone(w, me, 0)
	mark.cash = 50
	_walk(w, sched, mark, me.position, Vector2(1, 0))
	PickpocketSystem.start(w, state, mark.id)
	var result := {}
	for i in 400:
		mark.position += Vector2(1.2 / 60.0, 0)
		me.position = mark.position - Vector2(1.0, 0)
		result = PickpocketSystem.step(w, me, state, 1.0 / 60.0)
		if not result.is_empty():
			break
	print("from behind: ", result)
	ok = _check(result.get("effect", "") == "pickpocket" and mark.cash < 50, "staying behind them lifts their cash") and ok
	# in front of them
	var other := _someone(w, me, 1)
	_walk(w, sched, other, me.position + Vector2(0, 30), Vector2(1, 0))
	PickpocketSystem.start(w, state, other.id)
	result = {}
	for i in 200:
		other.position += Vector2(1.2 / 60.0, 0)
		me.position = other.position + Vector2(1.0, 0)
		result = PickpocketSystem.step(w, me, state, 1.0 / 60.0)
		if not result.is_empty():
			break
	print("in front: ", result)
	ok = _check(result.get("reason", "") == "lift_caught", "in front of them you get caught") and ok
	state.lift = {}

	# a gun up
	var rx := w.find_system(ReactionSystem) as ReactionSystem
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	me.position = city.spawn
	w.reindex_position(me.id)
	var front := _someone(w, me, 2)
	var side := _someone(w, me, 3)
	_place(w, sched, front, me.position + Vector2(3, 0))
	_place(w, sched, side, me.position + Vector2(0, 8))
	state.weapon = &"pistol"
	state.aiming = true
	state.aim_point = me.position + Vector2(10, 0)
	rx.process_entities(players, 0.0, w.tick - w.tick % ReactionSystem.EVERY + ReactionSystem.PHASE)
	print("gun up: hands up %d, ran %d" % [rx.hands_up, rx.ran])
	ok = _check(rx.hands_up >= 1 and rx.ran >= 1, "the one at the barrel freezes, the others run") and ok
	state.aiming = false

	# a body
	var ran := rx.ran
	var body := _someone(w, me, 4)
	body.is_down = true
	me.position = city.spawn + Vector2(0, 60)
	w.reindex_position(me.id)
	_place(w, sched, body, me.position + Vector2(2, 0))
	var witness := _someone(w, me, 5)
	_place(w, sched, witness, me.position + Vector2(6, 0))
	rx.process_entities(players, 0.0, w.tick - w.tick % ReactionSystem.EVERY + ReactionSystem.PHASE + ReactionSystem.EVERY)
	ok = _check(rx.ran > ran, "people run from a body") and ok

	# a gang corner
	var t := TerritorySystem.data(w)
	var spot := Vector2.INF
	var gang := &""
	for c in t.cells:
		var g := TerritorySystem.controller(t, c)
		if g != &"" and g != TerritorySystem.PLAYER and Hoods.is_block(c):
			spot = TerritoryData.centre_of(c)
			gang = g
			if TerritoryData.turf_of(spot) == c:
				break
	var member: NPCData = null
	for m in (w.entities[gang].get_component(ComponentNames.GANG) as GangData).member_npc_ids:
		var n: NPCData = w.entities[m].get_component(ComponentNames.NPC)
		if not n.is_down and not n.is_crew:
			member = n
			break
	me.position = spot
	w.reindex_position(me.id)
	_place(w, sched, member, spot + Vector2(3, 0))
	var said := state.message_serial
	var t0 := w.tick - w.tick % ReactionSystem.EVERY + ReactionSystem.PHASE + ReactionSystem.EVERY * 4
	rx.process_entities(players, 0.0, t0)
	var warned := state.message_serial > said
	var combat0 := w.find_system(NPCCombatSystem) as NPCCombatSystem
	rx.process_entities(players, 0.0, t0 + int(ReactionSystem.WARN_S * SimClock.TICKS_PER_SECOND) + ReactionSystem.EVERY)
	ok = _check(not combat0.hostile.has(member.id), "a passer-by with no gun out is only warned") and ok
	state.weapon = &"pistol"
	state.aiming = true
	rx.process_entities(players, 0.0, t0 + int(ReactionSystem.WARN_S * SimClock.TICKS_PER_SECOND) + ReactionSystem.EVERY * 2)
	var combat := w.find_system(NPCCombatSystem) as NPCCombatSystem
	print("gang corner: warned %s, then they come: %s" % [warned, combat.hostile.has(member.id)])
	ok = _check(warned and combat.hostile.has(member.id), "a gang warns you off its block, then comes for you") and ok
	SimNav.uninstall()
	if ok:
		print("PICKPOCKET_REACTIONS_VERIFY: PASS")
	quit(0 if ok else 1)

func _walk(w: World, sched: NPCScheduleSystem, n: NPCData, at: Vector2, dir: Vector2) -> void:
	_place(w, sched, n, at)
	sched.street.start_trip(n, [], at + dir * 300.0, SimUnits.WALK)

func _place(w: World, sched: NPCScheduleSystem, n: NPCData, at: Vector2) -> void:
	n.position = at
	n.indoors = false
	w.reindex_position(n.id)
	sched.street.step_out(n)

func _someone(w: World, me: NPCData, skip: int) -> NPCData:
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_down or n.is_fixer) and n.gang_id == &"":
			if skip == 0:
				return n
			skip -= 1
	return null

func _check(good: bool, what: String) -> bool:
	if not good:
		print("PICKPOCKET_REACTIONS_VERIFY: FAIL - ", what)
	return good
