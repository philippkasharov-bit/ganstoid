## Composition root for world gen: runs CityGenerator then PopulationSeeder
## against one World, with one seed. Call this once at new-game start; it's
## the only entry point Phase 1 game-start code should need from this folder.
class_name WorldGenerator
extends RefCounted

static func generate_new_game(world: World, seed: int, grid_width: int, grid_height: int, population_count: int) -> void:
	var building_ids := CityGenerator.generate(world, seed, grid_width, grid_height)
	# Offset the population seed from the city seed so changing one doesn't
	# silently reshuffle the other when tuning either in isolation.
	PopulationSeeder.seed(world, seed + 1, population_count, building_ids)
