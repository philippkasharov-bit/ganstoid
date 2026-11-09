## Batch 21: a working crew member on a HOT corner gets busted when a cop
## reaches them -- not on a cool corner, not without a cop, never lookouts
## or drivers; the bust costs the crew member and what they held, never
## the player's heat.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	var cops := []
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)
			cops.append(n)
	var cop: NPCData = cops[0]
	var building: BuildingData = world.get_entities_with_component(ComponentNames.BUILDING).values()[0].get_component(ComponentNames.BUILDING)
	var spot := building.position

	var dealer := _crew(world, state, 0, GanstoidEnums.CrewRole.DEALER, spot)
	dealer.crew_stash = 4
	dealer.crew_earnings = 30
	var lookout := _crew(world, state, 1, GanstoidEnums.CrewRole.LOOKOUT, spot)

	# Cool corner + cop right there: no bust.
	building.crime_heat = 0.0
	_put(world, cop, spot)
	assert(not CrewBustSystem.corner_is_hot(world, spot), "corner is cool")
	_warm_tick(world)
	assert(state.crew_ids.has(dealer.id), "no evidence on the corner -> no bust")

	# Hot corner, no cop: no bust.
	building.crime_heat = 0.9
	_put(world, cop, Vector2(-100000, -100000))
	_warm_tick(world)
	assert(state.crew_ids.has(dealer.id), "hot but no cop -> no bust yet")

	# Hot corner + cop: dealer busted, lookout untouched.
	building.crime_heat = 0.9
	_put(world, cop, spot)
	_warm_tick(world)
	assert(not state.crew_ids.has(dealer.id) and not dealer.is_crew, "dealer busted")
	assert(dealer.crew_stash == 0 and dealer.crew_earnings == 0, "product and cash seized")
	assert(dealer.recruit_refused, "won't rejoin")
	assert(state.crew_ids.has(lookout.id), "lookouts commit nothing -> never busted")
	assert(state.law_tier == GanstoidEnums.LawTier.CLEAN, "player's heat untouched")

	# Muscle is exposed too.
	var muscle := _crew(world, state, 2, GanstoidEnums.CrewRole.MUSCLE, spot)
	building.crime_heat = 0.9
	_warm_tick(world)
	assert(not state.crew_ids.has(muscle.id), "muscle on a hot block gets busted too")

	print("PHASE3_CREW_BUST_VERIFY: PASS")
	quit()

func _warm_tick(world: World) -> void:
	for i in World.WARM_TICK_INTERVAL:
		world.step(1.0 / 60.0)

func _put(world: World, npc: NPCData, at: Vector2) -> void:
	npc.position = at
	world.reindex_position(npc.id)

func _crew(world: World, state: PlayerStateData, index: int, role: GanstoidEnums.CrewRole, at: Vector2) -> NPCData:
	var found := 0
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n == null or n.is_cop or n.is_dealer or n.is_crew or e.has_component(ComponentNames.PLAYER_STATE):
			continue
		if found == index:
			n.is_crew = true
			n.crew_role = role
			n.post_position = at
			_put(world, n, at)
			state.crew_ids.append(id)
			return n
		found += 1
	return null
