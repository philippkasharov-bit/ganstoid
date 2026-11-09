## Batch 15: recruiting -- refusals, willingness inputs, acceptance
## bookkeeping, crew trailing the player, crew never acting as witnesses.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	world.runtime_rng.seed = 777
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)

	var civs := _civilians(world)
	var c0: NPCData = civs[0]

	# Willingness inputs each raise the chance.
	var w0 := CrewSystem.willingness(world, c0)
	c0.recognition_chance = 1.0
	assert(CrewSystem.willingness(world, c0) > w0, "having seen you work raises willingness")
	c0.recognition_chance = 0.0

	# Refusals.
	assert(CrewSystem.recruit(world, c0.id)["reason"] == "too_far", "must be close")
	_stand_next_to(world, pnpc, c0)
	pnpc.cash = 0
	assert(CrewSystem.recruit(world, c0.id)["reason"] == "cant_afford", "must afford the cut")
	var dealer := _first(world, true)
	assert(CrewSystem.recruit(world, dealer)["reason"] == "not_recruitable", "dealers aren't recruitable")

	# Pitch civilians until one says yes; every no is final.
	pnpc.cash = 10000
	var recruited: StringName = &""
	for c in civs:
		_stand_next_to(world, pnpc, c)
		var r := CrewSystem.recruit(world, c.id)
		if r["ok"]:
			recruited = c.id
			break
		assert(r["reason"] == "recruit_refused" and c.recruit_refused, "a no gets remembered")
		assert(CrewSystem.recruit(world, c.id)["reason"] == "already_refused", "can't re-roll a no")
	assert(recruited != &"", "someone in the city should say yes")
	assert(state.crew_ids == [recruited], "crew roster updated")
	assert(world.entities[recruited].get_component(ComponentNames.NPC).is_crew, "recruit flagged as crew")
	assert(CrewSystem.recruit(world, recruited)["reason"] == "not_recruitable", "can't recruit crew twice")

	# Crew trail the player.
	var crew_npc: NPCData = world.entities[recruited].get_component(ComponentNames.NPC)
	pnpc.position += Vector2(300, 0)
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	for i in 600:
		world.step(1.0 / 60.0)
	assert(crew_npc.position.distance_to(pnpc.position) <= CrewSystem.FOLLOW_RADIUS + 5.0, "crew should catch up and loiter near you")

	# Crew never witness for the cops.
	crew_npc.recognition_chance = 0.0
	CrimeSystem.broadcast_witnesses(world, crew_npc.position, 0.9)
	assert(crew_npc.recognition_chance == 0.0, "crew are skipped as witnesses")

	# Cap.
	while state.crew_ids.size() < CrewSystem.MAX_CREW:
		state.crew_ids.append(&"filler")
	var spare: NPCData = civs[civs.size() - 1]
	spare.recruit_refused = false
	_stand_next_to(world, pnpc, spare)
	assert(CrewSystem.recruit(world, spare.id)["reason"] == "crew_full", "crew is capped")

	print("PHASE3_CREW_RECRUIT_VERIFY: PASS")
	quit()

func _stand_next_to(world: World, pnpc: NPCData, npc: NPCData) -> void:
	pnpc.position = npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

func _civilians(world: World) -> Array:
	var out := []
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != null and not n.is_cop and not n.is_dealer and not e.has_component(ComponentNames.PLAYER_STATE):
			out.append(n)
	return out

func _first(world: World, dealer: bool) -> StringName:
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_dealer == dealer and not n.is_cop:
			return id
	return &""
