## Standalone verification harness for the building-robbery action
## (CrimeSystem.rob_building, Phase 2 batch 6). Dev tool, not shipped
## content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_building_robbery.gd
##
## Batch 10 (locked): Part 2 used to also exercise CopAISystem's guard-bias
## patrol re-anchor here, back when has_been_hit (a permanent boolean) was
## its only trigger. Batch 10 replaced that trigger with BuildingData.
## crime_heat (a decaying scalar, generalized to any crime type) -- a
## fundamentally different shape that a 3000-tick "stays tight the whole
## time" assertion no longer fits (heat is DESIGNED to fade, same "use it
## or lose it" cadence as market reputation/gang standing). That coverage
## now lives in its own dedicated harness, debug/verify_phase2_patrol_heat_
## and_raids.gd, alongside the new raid behavior it feeds. This file keeps
## testing exactly what it always owned: the robbery action itself,
## including has_been_hit still flipping (unconditional on every robbery,
## unaffected by this batch).
extends SceneTree

const PATROL_STEPS := 3000

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)

	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)

	# --- Part 1: basic rob/too-far/nothing-to-take, against a real revenue
	# building (not a synthetic one), so the ordinary economy-building path
	# is exercised as-is from worldgen.
	var building_id := _find_a_revenue_building(world)
	assert(building_id != &"", "worldgen should produce at least one revenue-earning building")
	var building: BuildingData = world.entities[building_id].get_component(ComponentNames.BUILDING)
	var starting_cash := building.cash_on_hand
	assert(starting_cash > 0, "a revenue building should start with cash_on_hand banked (one day's take)")

	player_npc.position = building.position + Vector2(CrimeSystem.INTERACT_RADIUS + 50.0, 0)
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	var too_far := CrimeSystem.rob_building(world, building_id)
	assert(not too_far.get("ok", false) and too_far.get("reason", "") == "too_far", "robbery from outside INTERACT_RADIUS must be refused")

	player_npc.position = building.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	var starting_player_cash: int = player_npc.cash
	var first_rob := CrimeSystem.rob_building(world, building_id)
	assert(first_rob.get("ok", false), "robbery in range of a building with cash on hand should succeed")
	var taken: int = first_rob.get("taken", 0)
	assert(taken > 0, "a successful robbery must actually take something")
	assert(player_npc.cash == starting_player_cash + taken, "the taken amount must be credited to the player's cash exactly")
	assert(building.cash_on_hand == starting_cash - taken, "the taken amount must be drained from the building's cash_on_hand exactly")
	assert(building.has_been_hit, "has_been_hit must flip true on a successful robbery")
	print("robbed %s for %d (cash_on_hand %d -> %d)" % [building_id, taken, starting_cash, building.cash_on_hand])

	# Drain it the rest of the way, then confirm a dry building refuses cleanly.
	while building.cash_on_hand > 0:
		CrimeSystem.rob_building(world, building_id)
	var dry_rob := CrimeSystem.rob_building(world, building_id)
	assert(not dry_rob.get("ok", false) and dry_rob.get("reason", "") == "nothing_to_take", "robbing a building with zero cash_on_hand must be refused, not go negative")

	# --- Part 2: a second, controlled robbery (a cop's own depot, picked
	# for a deterministic location rather than a random city building)
	# confirming has_been_hit flips exactly the same way regardless of
	# which building gets hit. The guard-bias/raid consequences that used
	# to be checked here now live in verify_phase2_patrol_heat_and_raids.gd
	# (see this file's top doc comment).
	var cop_id := _find_a_cop(world)
	assert(cop_id != &"", "PopulationSeeder should have seeded at least one cop")
	var cop_npc: NPCData = world.entities[cop_id].get_component(ComponentNames.NPC)
	var depot_id := cop_npc.home_building_id
	var depot: BuildingData = world.entities[depot_id].get_component(ComponentNames.BUILDING)
	depot.cash_on_hand = 500

	player_npc.position = depot.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	var depot_rob := CrimeSystem.rob_building(world, depot_id)
	assert(depot_rob.get("ok", false), "robbing the cop's own depot (given cash_on_hand) should succeed the same as any other building")
	assert(depot.has_been_hit, "the depot should now read as a hit building")

	print("PHASE2_BUILDING_ROBBERY_VERIFY: PASS")
	quit()

func _find_a_revenue_building(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building != null and building.daily_revenue > 0 and building.cash_on_hand > 0:
			return id
	return &""

func _find_a_cop(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_cop:
			return id
	return &""
