## Composition root for new-game start: runs CityGenerator, then
## PopulationSeeder, then spawns the player, against one World, with one
## seed. Call this once at new-game start; it's the only entry point
## Phase 1 game-start code should need from this folder.
class_name WorldGenerator
extends RefCounted

static func generate_new_game(world: World, seed: int, grid_width: int, grid_height: int, population_count: int) -> void:
	var building_ids := CityGenerator.generate(world, seed, grid_width, grid_height)
	# Offset the population seed from the city seed so changing one doesn't
	# silently reshuffle the other when tuning either in isolation.
	PopulationSeeder.seed(world, seed + 1, population_count, building_ids)
	GoodsCatalog.seed_goods(world)
	_spawn_player(world, building_ids)

## MG1a: new game on the REAL city. Only buildings within `radius` metres of
## `centre` are simulated (the active district); positions are metres.
static func generate_real_city_game(world: World, seed: int, city: CityData, centre: Vector2, radius: float, population_count: int) -> void:
	var building_ids := CityRoles.generate(world, seed, city, centre, radius)
	PopulationSeeder.seed(world, seed + 1, population_count, building_ids)
	GoodsCatalog.seed_goods(world)
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
	PlayerFactory.spawn(world, home.position, best_id)

## Player starts at the first RESIDENCE lot CityGenerator produced --
## deterministic given the seed, same as everything else in world gen.
## Falls back to Vector2.ZERO only if a city somehow has none (PopulationSeeder
## already asserts this can't happen, so this is defense-in-depth, not a
## real path).
static func _spawn_player(world: World, building_ids: Array[StringName]) -> void:
	var spawn_position := Vector2.ZERO
	var spawn_building_id: StringName = &""
	for id in building_ids:
		var building: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if building.building_type == GanstoidEnums.BuildingType.RESIDENCE:
			spawn_position = building.position
			spawn_building_id = id
			break
	PlayerFactory.spawn(world, spawn_position, spawn_building_id)
