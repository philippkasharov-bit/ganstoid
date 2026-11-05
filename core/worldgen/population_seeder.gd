## Seeds initial NPC population onto an already-generated city (CityGenerator
## must run first — this reads building_ids it produced). Kept separate from
## city layout so population density/employment can be retuned independently.
class_name PopulationSeeder
extends RefCounted

const EMPLOYMENT_RATE := 0.7  # fraction of NPCs assigned a work_building_id
const UNEMPLOYED_STARTING_CASH := Vector2i(0, 50)
const EMPLOYED_CASH_MULTIPLIER := 3  # starting cash scales with employer's daily_revenue

static func seed(world: World, seed: int, population_count: int, building_ids: Array[StringName]) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var residences := _filter_by_type(world, building_ids, GanstoidEnums.BuildingType.RESIDENCE)
	var workplaces := _filter_by_type(world, building_ids, GanstoidEnums.BuildingType.LEGIT_BUSINESS)
	assert(not residences.is_empty(), "PopulationSeeder requires at least one RESIDENCE building")

	var npc_ids: Array[StringName] = []
	for i in population_count:
		var npc := _build_npc(rng, i, residences, workplaces, world)
		var entity := Entity.new(npc.id)
		entity.add_component(npc)
		world.register_entity(entity)
		npc_ids.append(npc.id)
	return npc_ids

static func _build_npc(
	rng: RandomNumberGenerator,
	index: int,
	residences: Array[StringName],
	workplaces: Array[StringName],
	world: World
) -> NPCData:
	var npc := NPCData.new()
	npc.id = StringName("npc_%d" % index)
	npc.home_building_id = residences[rng.randi() % residences.size()]

	var is_employed := not workplaces.is_empty() and rng.randf() < EMPLOYMENT_RATE
	if is_employed:
		npc.work_building_id = workplaces[rng.randi() % workplaces.size()]
		var workplace: BuildingData = world.entities[npc.work_building_id].get_component("BuildingData")
		npc.cash = workplace.daily_revenue * EMPLOYED_CASH_MULTIPLIER
	else:
		npc.cash = rng.randi_range(UNEMPLOYED_STARTING_CASH.x, UNEMPLOYED_STARTING_CASH.y)

	return npc

static func _filter_by_type(
	world: World, building_ids: Array[StringName], target_type: GanstoidEnums.BuildingType
) -> Array[StringName]:
	var matches: Array[StringName] = []
	for id in building_ids:
		var building: BuildingData = world.entities[id].get_component("BuildingData")
		if building.building_type == target_type:
			matches.append(id)
	return matches
