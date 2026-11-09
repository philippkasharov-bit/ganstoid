## Batch 20: driver rides with you, speeds you up, more so on a getaway,
## beats a responding cop's speed, doesn't stack, and can be let out.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	var crews := _make_crew(world, state, 2)
	var a: NPCData = crews[0]
	var b: NPCData = crews[1]

	assert(CrewSystem.player_speed_multiplier(world, state) == 1.0, "no driver, no bonus")
	assert(CrewSystem.toggle_driver(world, a.id)["effect"] == "driver_assigned", "assigned")
	assert(is_equal_approx(CrewSystem.player_speed_multiplier(world, state), CrewSystem.DRIVER_SPEED_MULT), "driver bonus")
	state.law_tier = GanstoidEnums.LawTier.WARNED
	assert(is_equal_approx(CrewSystem.player_speed_multiplier(world, state), CrewSystem.GETAWAY_SPEED_MULT), "getaway bonus with heat")
	assert(PlayerInputSystem.MOVE_SPEED * CrewSystem.GETAWAY_SPEED_MULT > CopAISystem.RESPONSE_SPEED, "getaway outruns a responding cop")
	assert(PlayerInputSystem.MOVE_SPEED < CopAISystem.RESPONSE_SPEED, "on foot you can't")
	state.law_tier = GanstoidEnums.LawTier.CLEAN

	# Two drivers don't stack.
	CrewSystem.toggle_driver(world, b.id)
	assert(is_equal_approx(CrewSystem.player_speed_multiplier(world, state), CrewSystem.DRIVER_SPEED_MULT), "no stacking")
	CrewSystem.toggle_driver(world, b.id)

	# Rides with you wherever you go.
	pnpc.position += Vector2(600, 300)
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	world.step(1.0 / 60.0)
	assert(a.position.distance_to(pnpc.position) < 20.0, "driver stays with you")

	# Busy crew can't drive; driver can't be posted elsewhere.
	assert(CrewSystem.toggle_post(world, a.id)["reason"] == "crew_busy", "driver isn't a lookout")
	CrewSystem.toggle_post(world, b.id)
	assert(CrewSystem.toggle_driver(world, b.id)["reason"] == "crew_busy", "lookout must be recalled first")

	# Let them out.
	assert(CrewSystem.toggle_driver(world, a.id)["effect"] == "driver_dismissed", "dismissed")
	assert(CrewSystem.player_speed_multiplier(world, state) == 1.0, "back on foot")

	print("PHASE3_CREW_DRIVER_VERIFY: PASS")
	quit()

func _make_crew(world: World, state: PlayerStateData, count: int) -> Array:
	var out := []
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n == null or n.is_cop or n.is_dealer or e.has_component(ComponentNames.PLAYER_STATE):
			continue
		n.is_crew = true
		state.crew_ids.append(id)
		out.append(n)
		if out.size() == count:
			break
	return out
