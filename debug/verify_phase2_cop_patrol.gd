## Standalone verification harness for cop patrol realism (WanderBehavior-
## based leash + dwell on top of CopAISystem's existing patrol/alert
## loop). Dev tool, not shipped content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_cop_patrol.gd
extends SceneTree

## A few day-cycles' worth of pure patrol (no crime triggered) -- long
## enough that an unleashed random walk (the pre-fix bug) would have
## wandered well past PATROL_WANDER_RADIUS from depot by the end, and long
## enough to be confident any dwell pauses that exist actually show up.
const PATROL_STEPS := 6000

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)

	var cop_id := _find_a_cop(world)
	assert(cop_id != &"", "PopulationSeeder should have seeded at least one cop")
	var cop_npc: NPCData = world.entities[cop_id].get_component(ComponentNames.NPC)
	assert(cop_npc.home_building_id != &"", "cop should have a home_building_id (patrol depot)")
	var depot: BuildingData = world.entities[cop_npc.home_building_id].get_component(ComponentNames.BUILDING)
	print("cop=%s depot=%s" % [cop_id, depot.position])

	var max_dist_from_depot := 0.0
	var dwelling_ticks := 0
	var last_pos := cop_npc.position
	for i in PATROL_STEPS:
		world.step(1.0 / 60.0)
		max_dist_from_depot = maxf(max_dist_from_depot, cop_npc.position.distance_to(depot.position))
		if cop_npc.position.distance_to(last_pos) < 0.01:
			dwelling_ticks += 1
		last_pos = cop_npc.position

	print("max distance from depot over %d patrol ticks: %.1f (leash radius: %.1f)" % [PATROL_STEPS, max_dist_from_depot, CopAISystem.PATROL_WANDER_RADIUS])
	assert(max_dist_from_depot <= CopAISystem.PATROL_WANDER_RADIUS + 1.0, "patrol must stay leashed to depot -- never drift past the wander radius")
	print("ticks spent dwelling (stationary) during patrol: %d / %d" % [dwelling_ticks, PATROL_STEPS])
	assert(dwelling_ticks > 0, "patrol must include real dwell pauses, not constant motion")

	# Regression: the alert -> chase -> arrest loop (Phase 1) still works
	# exactly as before -- patrol realism changed how a cop moves while NOT
	# alerted, it must not have touched the alert path itself.
	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	player_npc.position = cop_npc.position
	# G2: the long patrol run above lasts game days; the player would have died of thirst
	player_npc.hunger = 1.0
	player_npc.thirst = 1.0
	player_npc.health = 1.0
	player_npc.is_down = false
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	player_state.law_tier = GanstoidEnums.LawTier.WARNED
	world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {
		"position": cop_npc.position,
		"severity": 0.5,
		"tick": world.tick,
		"witness_id": cop_id,
	})
	for i in 10:
		world.step(1.0 / 60.0)
	var home: BuildingData = world.entities[player_npc.home_building_id].get_component(ComponentNames.BUILDING)
	print("after alert: law_tier=%s player_pos=%s home_pos=%s" % [player_state.law_tier, player_npc.position, home.position])
	assert(player_state.law_tier == GanstoidEnums.LawTier.CLEAN, "cop standing on the player when alerted should arrest immediately, same as before this batch")
	assert(player_npc.position.distance_to(home.position) < 1.0, "arrest should still send the player home, same as before this batch")

	print("PHASE2_COP_PATROL_VERIFY: PASS")
	quit()

func _find_a_cop(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_cop:
			return id
	return &""
