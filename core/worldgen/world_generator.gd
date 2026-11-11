## Composition root for new-game start: gives the fixed real city's buildings
## their roles (CityRoles), then PopulationSeeder, then spawns the player,
## against one World, with one seed. Call this once at new-game start; it's the
## only entry point game-start code should need from this folder.
class_name WorldGenerator
extends RefCounted

## MG1a: new game on the REAL city. Only buildings within `radius` metres of
## `centre` are simulated (the active district); positions are metres.
const STARTING_CASH := 40   # G1: broke on day one: enough for a few meals

static func generate_real_city_game(world: World, seed: int, city: CityData, centre: Vector2, radius: float, population_count: int) -> void:
	var building_ids := CityRoles.generate(world, seed, city, centre, radius)
	PopulationSeeder.seed(world, seed + 1, population_count, building_ids)
	GoodsCatalog.seed_goods(world)
	VehicleSeeder.seed(world, seed + 2, city, centre, radius)
	TerritorySystem.seed(world)
	_spawn_player_near(world, building_ids, centre)

## Player starts at the home nearest the district centre.
static func _spawn_player_near(world: World, building_ids: Array[StringName], centre: Vector2) -> void:
	var best_id: StringName = &""
	var best_d := INF
	for id in building_ids:
		var building: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		var d := building.position.distance_to(centre)
		if building.building_type == GanstoidEnums.BuildingType.RESIDENCE and d < best_d:
			best_d = d
			best_id = id
	var home: BuildingData = world.entities[best_id].get_component(ComponentNames.BUILDING)
	PlayerFactory.spawn(world, home.position, best_id, STARTING_CASH)
