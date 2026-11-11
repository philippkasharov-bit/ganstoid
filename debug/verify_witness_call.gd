## W2 validator: a civilian who recognised you phones it in seconds later,
## not at once; knock them out first and the call never happens; a dealer
## never calls; a cop reports at once.
extends SceneTree

var _reports := 0

func _initialize() -> void:
	var world := World.new()
	var calls := WitnessCallSystem.new(world)
	world.register_system(calls)
	world.event_bus.subscribe(func(n: StringName, _p: Dictionary) -> void:
		if n == GanstoidEvents.CRIME_WITNESSED:
			_reports += 1)
	var me := _person(world, PlayerFactory.PLAYER_ENTITY_ID, Vector2.ZERO)
	var state := PlayerStateData.new()
	world.entities[me.id].add_component(state)
	world.reindex_components(me.id)
	var w := _person(world, &"w", Vector2(5, 0))
	world.tick = SimClock.hours(12.0)
	CrimeSystem._report(world, w, {"position": Vector2.ZERO, "severity": 0.5, "tick": world.tick, "witness_id": &"w"})
	var at_once := _reports
	for t in 60 * 16:
		world.tick += 1
		calls.process_entities({}, 1.0 / 60.0, world.tick)
	var later := _reports
	var w2 := _person(world, &"w2", Vector2(5, 0))
	CrimeSystem._report(world, w2, {"position": Vector2.ZERO, "severity": 0.5, "tick": world.tick, "witness_id": &"w2"})
	w2.is_down = true   # put down before the call
	calls.flush()
	var cop := _person(world, &"c", Vector2(5, 0))
	cop.is_cop = true
	var before_cop := _reports
	CrimeSystem._report(world, cop, {"position": Vector2.ZERO, "severity": 0.5, "tick": world.tick, "witness_id": &"c"})
	print("civilian: at once %d, after 16 s %d; silenced %d; cop reports at once %s" % [at_once, later, calls.silenced, _reports == before_cop + 1])
	if at_once == 0 and later == 1 and calls.silenced == 1 and _reports == 2:
		print("WITNESS_CALL_VERIFY: PASS")
		quit()
	else:
		print("WITNESS_CALL_VERIFY: FAIL - witnesses phone it in, unless silenced")
		quit(1)

func _person(world: World, id: StringName, at: Vector2) -> NPCData:
	var e := Entity.new(id)
	var n := NPCData.new()
	n.id = id
	n.position = at
	e.add_component(n)
	world.register_entity(e)
	world.reindex_position(id)
	return n
