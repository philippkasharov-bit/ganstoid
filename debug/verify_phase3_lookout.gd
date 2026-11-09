## Batch 17: posting/recalling a lookout, lookout holding its post, and the
## cover cutting recognitions roughly in half -- never adding any.
extends SceneTree

var _witnessed := 0

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	world.runtime_rng.seed = 4242
	world.event_bus.subscribe(_on_event)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)
	var civs := _civilians(world)
	var crew: NPCData = civs[0]
	crew.is_crew = true
	state.crew_ids.append(crew.id)

	# Post where they stand; they hold the spot while you walk off.
	assert(CrewSystem.toggle_post(world, crew.id)["effect"] == "posted", "posting works")
	var post := crew.post_position
	pnpc.position = post + Vector2(400, 0)
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	for i in 1200:
		world.step(1.0 / 60.0)
	assert(crew.position.distance_to(post) <= CrewSystem.LOOKOUT_LOITER_RADIUS + 2.0, "lookout holds the post")
	assert(CrewSystem.lookout_covers(world, post + Vector2(50, 0)), "covers nearby")
	assert(not CrewSystem.lookout_covers(world, pnpc.position), "doesn't cover far away")

	# Cover cuts recognitions: a sure-thing witness, many crimes, with/without cover.
	# Clear the street first so the one test witness is the only witness
	# (civilians now start at their real homes, some of them right here).
	for c in civs:
		if c != crew:
			c.position = Vector2(-50000, -50000)
			c.is_busy = true  # keep them parked
			world.reindex_position(c.id)
	var witness: NPCData = civs[1]
	var uncovered := _count_reports(world, witness, pnpc.position, 400)
	var covered := _count_reports(world, witness, post + Vector2(20, 0), 400)
	print("reports uncovered=%d covered=%d" % [uncovered, covered])
	assert(uncovered == 400, "a sure witness always reports without cover")
	assert(covered > 140 and covered < 260, "lookout waves off about half")

	# Recall.
	assert(CrewSystem.toggle_post(world, crew.id)["effect"] == "recalled", "recall works")
	assert(crew.crew_role == GanstoidEnums.CrewRole.UNASSIGNED and not CrewSystem.lookout_covers(world, post), "recalled lookout stops covering")

	print("PHASE3_LOOKOUT_VERIFY: PASS")
	quit()

func _count_reports(world: World, witness: NPCData, at: Vector2, n: int) -> int:
	_witnessed = 0
	witness.position = at
	world.reindex_position(witness.id)
	for i in n:
		witness.recognition_chance = 1.0
		CrimeSystem.broadcast_witnesses(world, at, 0.1)
	return _witnessed

func _on_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == GanstoidEvents.CRIME_WITNESSED:
		_witnessed += 1

func _civilians(world: World) -> Array:
	var out := []
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != null and not n.is_cop and not n.is_dealer and not e.has_component(ComponentNames.PLAYER_STATE):
			out.append(n)
	return out
