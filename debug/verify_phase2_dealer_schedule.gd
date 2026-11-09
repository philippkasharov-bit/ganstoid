## Standalone verification harness for the dealer day/night schedule
## (PopulationSeeder's home/work assignment riding NPCScheduleSystem's
## existing two-state cycle, now with per-NPC schedule stagger + idle
## wander on top -- see NPCScheduleSystem's doc comment). Dev tool, not
## shipped content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_dealer_schedule.gd
extends SceneTree

## Arrival tolerance -- an idling NPC drifts within IDLE_WANDER_RADIUS of
## their destination rather than freezing on its exact pixel, so "arrived"
## means "within that radius," not "within a few px." A couple of px of
## slack on top covers float rounding at the boundary.
const ARRIVAL_TOLERANCE := NPCScheduleSystem.IDLE_WANDER_RADIUS + 2.0

## Generous per-phase step budget. Deliberately NOT computed from a fixed
## tick count the way the pre-stagger version of this test was -- every
## NPC's work<->home flip is now jittered per-id (NPCScheduleSystem.
## schedule_offset), so a fixed "step N ticks then assert" budget would be
## right for some dealers and wrong for others depending on their offset.
## Stepping until the position actually gets close, capped at just over
## one full day cycle, is correct regardless of which dealer gets picked or
## what their offset happens to be.
const MAX_STEPS_PER_PHASE := 2000  # > TestWorlds.FAST_DAY_TICKS (1800), covers any offset

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)

	var dealer_id := _find_a_dealer(world)
	assert(dealer_id != &"", "PopulationSeeder should have seeded at least one dealer")
	var dealer_npc: NPCData = world.entities[dealer_id].get_component(ComponentNames.NPC)
	assert(dealer_npc.home_building_id != &"", "dealer should have a home_building_id")
	assert(dealer_npc.work_building_id != &"", "dealer should have a work_building_id")

	var home: BuildingData = world.entities[dealer_npc.home_building_id].get_component(ComponentNames.BUILDING)
	var work: BuildingData = world.entities[dealer_npc.work_building_id].get_component(ComponentNames.BUILDING)
	print("dealer=%s home=%s work=%s offset=%d" % [dealer_id, home.position, work.position, NPCScheduleSystem.schedule_offset(dealer_id)])
	assert(dealer_npc.position.distance_to(home.position) < 1.0, "dealer should start at home before the sim ticks")

	var steps_to_work := _step_until_near(world, dealer_npc, work.position, ARRIVAL_TOLERANCE, MAX_STEPS_PER_PHASE)
	print("steps to reach work: %s (pos=%s, tick=%d)" % [steps_to_work, dealer_npc.position, world.tick])
	assert(steps_to_work >= 0, "dealer should have walked to their work (selling) spot sometime during their work hours")

	var steps_to_home := _step_until_near(world, dealer_npc, home.position, ARRIVAL_TOLERANCE, MAX_STEPS_PER_PHASE)
	print("steps to return home: %s (pos=%s, tick=%d)" % [steps_to_home, dealer_npc.position, world.tick])
	assert(steps_to_home >= 0, "dealer should have walked home sometime during their off hours")

	# Buying from them at their home address should work exactly like buying
	# from them out on the street -- DealSystem only cares about current
	# position, not which building they're standing at.
	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	player_npc.cash = 100
	player_npc.position = dealer_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	var buy_at_home := DealSystem.buy(world, dealer_id, &"weed")
	print("buy at dealer's home: ", buy_at_home)
	assert(buy_at_home.get("ok", false), "buying from a dealer at their home address should work the same as on the street")

	print("PHASE2_DEALER_SCHEDULE_VERIFY: PASS")
	quit()

## Steps the world until `moving.position` is within `tolerance` of
## `anchor`, up to `max_steps` steps. Returns the number of steps it took,
## or -1 if it never got there -- the caller asserts on that return value
## rather than this function asserting itself, so a failure prints both
## step counts' context (see call sites above) instead of just a bare
## "assertion failed" with no idea how close it got.
func _step_until_near(world: World, moving: NPCData, anchor: Vector2, tolerance: float, max_steps: int) -> int:
	for i in max_steps:
		if moving.position.distance_to(anchor) <= tolerance:
			return i
		world.step(1.0 / 60.0)
	return -1

func _find_a_dealer(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_dealer:
			return id
	return &""
