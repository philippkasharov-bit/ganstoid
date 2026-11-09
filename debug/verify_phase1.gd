## Standalone verification harness for the Phase 1 crime/witness/cop loop --
## not a shipped gameplay file, a dev tool. Run with:
##   godot --headless --path . --script res://debug/verify_phase1.gd
## Boots a World directly (no scene tree needed), forces a deterministic
## witness, commits a pickpocket, and steps the sim far enough for a nearby
## cop to respond and arrest -- proving the whole chain end to end, not just
## that each piece compiles in isolation.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)

	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)

	var victim_id: StringName = _find_nearest_civilian(world, player_npc.position)
	print("victim found: ", victim_id)
	var victim_npc: NPCData = world.entities[victim_id].get_component(ComponentNames.NPC)

	# Harness-only: teleport the player next to the victim so INTERACT_RADIUS
	# is satisfied, and force every nearby NPC's recognition_chance to 1.0 so
	# the witness roll is deterministic for this test (normal play rolls it).
	player_npc.position = victim_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	for id in world.spatial_index.query_nearby(player_npc.position):
		if id == PlayerFactory.PLAYER_ENTITY_ID:
			continue
		var entity: Entity = world.entities.get(id)
		var npc: NPCData = entity.get_component(ComponentNames.NPC) if entity else null
		if npc != null:
			npc.recognition_chance = 1.0

	print("before: player_cash=%d victim_cash=%d law_tier=%s" % [player_npc.cash, victim_npc.cash, player_state.law_tier])
	var result := CrimeSystem.commit_crime(world, GanstoidEnums.CrimeType.PICKPOCKET, victim_id)
	print("crime result: ", result)
	print("after crime: player_cash=%d victim_cash=%d law_tier=%s" % [player_npc.cash, victim_npc.cash, player_state.law_tier])

	assert(result.get("ok", false), "pickpocket should have succeeded")
	assert(player_state.law_tier == GanstoidEnums.LawTier.WARNED, "law_tier should have escalated to WARNED on a confirmed witness")

	# Place a cop just outside arrest range but inside broadcast range of the
	# crime, then step the world and confirm it closes in and arrests.
	var cop_id := _find_a_cop(world)
	print("cop found: ", cop_id)
	var cop_npc: NPCData = world.entities[cop_id].get_component(ComponentNames.NPC)
	cop_npc.position = player_npc.position + Vector2(200, 0)
	world.reindex_position(cop_id)

	for i in 400:
		world.step(1.0 / 60.0)

	print("final: player_cash=%d law_tier=%s player_pos=%s home_pos=%s" % [
		player_npc.cash, player_state.law_tier, player_npc.position,
		world.entities[player_npc.home_building_id].get_component(ComponentNames.BUILDING).position if player_npc.home_building_id != &"" else "n/a",
	])

	assert(player_state.law_tier == GanstoidEnums.LawTier.CLEAN, "cop should have arrested the player, resetting law_tier to CLEAN")
	print("PHASE1_VERIFY: PASS")
	quit()

func _find_nearest_civilian(world: World, from: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist := INF
	for id in world.entities:
		if id == PlayerFactory.PLAYER_ENTITY_ID:
			continue
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc == null or npc.is_cop:
			continue
		var d := npc.position.distance_to(from)
		if d < best_dist:
			best_dist = d
			best_id = id
	return best_id

func _find_a_cop(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_cop:
			return id
	return &""
