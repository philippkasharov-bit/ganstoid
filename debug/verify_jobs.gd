## JB1 validator on the real city: three fixers; offers are real targets;
## a hit pays on a knockout (60%) and raises your name; a car job pays when
## the car stops at the drop; a missed deadline costs you; heists unlock.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 5)
	var fixers := 0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		fixers += int(e.get_component(ComponentNames.NPC).is_fixer)
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var state: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var jobs := world.find_system(JobSystem) as JobSystem
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	var offers := JobSystem.offers(world, state, me)
	print("fixers %d, offers %s" % [fixers, offers.map(func(j: Dictionary) -> String: return j["kind"])])
	if not _check(fixers == 3 and offers.size() == 3, "three fixers, three offers"):
		return
	var cash := me.cash
	var hit := {"kind": "hit", "target": _someone(world), "pay": 500, "text": "t"}
	JobSystem.take(world, state, hit)
	var mark: NPCData = world.entities[hit["target"]].get_component(ComponentNames.NPC)
	mark.is_down = true
	mark.ko_until_tick = world.tick + 999
	jobs.process_entities(players, 0.0, world.tick)
	print("hit by knockout: paid %d, rep %.2f, job open %s" % [me.cash - cash, state.fixer_rep, not state.job.is_empty()])
	if not _check(me.cash - cash == 300 and state.job.is_empty() and state.fixer_rep > 0.1, "a knockout hit pays 60% and raises your name"):
		return
	var car_id: StringName = world.get_entities_with_component(ComponentNames.VEHICLE).keys()[0]
	var car: VehicleData = world.entities[car_id].get_component(ComponentNames.VEHICLE)
	JobSystem.take(world, state, {"kind": "car", "target": car_id, "drop": car.position + Vector2(300, 0), "pay": 250, "text": "c"})
	jobs.process_entities(players, 0.0, world.tick)
	var open_before := not state.job.is_empty()
	car.position += Vector2(296, 0)
	cash = me.cash
	jobs.process_entities(players, 0.0, world.tick)
	print("car job: open before the drop %s, paid at the drop %d" % [open_before, me.cash - cash])
	if not _check(open_before and me.cash - cash == 250, "the car pays at the drop"):
		return
	JobSystem.take(world, state, {"kind": "debt", "target": _someone(world), "pay": 120, "text": "d"})
	var rep := state.fixer_rep
	world.tick += SimClock.hours(25.0)
	jobs.process_entities(players, 0.0, world.tick)
	state.fixer_rep = 0.5
	var heist_offered := false
	for i in 10:
		for j in JobSystem.offers(world, state, me):
			heist_offered = heist_offered or j["kind"] == "heist"
	print("deadline missed: rep %.2f -> %.2f; heists offered at rep 0.5: %s" % [rep, rep - JobSystem.REP_LOSS, heist_offered])
	if not _check(state.job.is_empty() and heist_offered, "a missed deadline ends the job; heists unlock with a name"):
		return
	print("JOBS_VERIFY: PASS")
	quit()

func _someone(world: World) -> StringName:
	for id in world.get_entities_with_component(ComponentNames.NPC):
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if not n.is_cop and id != PlayerFactory.PLAYER_ENTITY_ID:
			return id
	return &""

func _check(good: bool, what: String) -> bool:
	if not good:
		print("JOBS_VERIFY: FAIL - ", what)
		quit(1)
	return good
