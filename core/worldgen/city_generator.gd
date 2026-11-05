## Procedural city layout: places buildings on a grid, seeded for determinism
## (same seed -> same city, required for Phase 6 save/load + testability).
## Produces only BuildingData entities — NPC population is PopulationSeeder's job,
## kept separate so either can be re-run/tuned independently.
class_name CityGenerator
extends RefCounted

const LOT_SPACING := 32.0  # pixels between adjacent lots, tunable per art scale

## Weighted distribution of building types per lot. Weights, not percentages —
## normalized internally, so they don't need to sum to 1.0.
const BUILDING_TYPE_WEIGHTS := {
	GanstoidEnums.BuildingType.RESIDENCE: 60,
	GanstoidEnums.BuildingType.LEGIT_BUSINESS: 30,
	GanstoidEnums.BuildingType.ILLEGAL_FRONT: 8,
	GanstoidEnums.BuildingType.SAFEHOUSE: 2,
}

## Revenue bands per building type (daily_revenue, cash_on_hand starting value).
## Illegal fronts and safehouses get no legitimate revenue line here —
## their economics come from Phase 2/4 systems, not world gen.
const REVENUE_BY_TYPE := {
	GanstoidEnums.BuildingType.RESIDENCE: Vector2i(0, 0),
	GanstoidEnums.BuildingType.LEGIT_BUSINESS: Vector2i(50, 200),
	GanstoidEnums.BuildingType.ILLEGAL_FRONT: Vector2i(0, 0),
	GanstoidEnums.BuildingType.SAFEHOUSE: Vector2i(0, 0),
}

static func generate(world: World, seed: int, grid_width: int, grid_height: int) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var building_ids: Array[StringName] = []
	for y in grid_height:
		for x in grid_width:
			var building := _build_at_lot(rng, x, y)
			world.register_entity(_wrap_entity(building))
			building_ids.append(building.id)
	return building_ids

static func _build_at_lot(rng: RandomNumberGenerator, x: int, y: int) -> BuildingData:
	var building := BuildingData.new()
	building.id = StringName("bldg_%d_%d" % [x, y])
	building.position = Vector2(x * LOT_SPACING, y * LOT_SPACING)
	building.building_type = _weighted_pick_type(rng)
	building.is_raidable = building.building_type in [
		GanstoidEnums.BuildingType.ILLEGAL_FRONT,
		GanstoidEnums.BuildingType.SAFEHOUSE,
	]
	var band: Vector2i = REVENUE_BY_TYPE[building.building_type]
	building.daily_revenue = rng.randi_range(band.x, band.y)
	building.cash_on_hand = building.daily_revenue  # starts with one day's take banked
	return building

static func _weighted_pick_type(rng: RandomNumberGenerator) -> GanstoidEnums.BuildingType:
	var total := 0
	for weight in BUILDING_TYPE_WEIGHTS.values():
		total += weight
	var roll := rng.randi_range(0, total - 1)
	var cumulative := 0
	for building_type in BUILDING_TYPE_WEIGHTS:
		cumulative += BUILDING_TYPE_WEIGHTS[building_type]
		if roll < cumulative:
			return building_type
	return GanstoidEnums.BuildingType.RESIDENCE  # unreachable; satisfies static type return

static func _wrap_entity(building: BuildingData) -> Entity:
	var entity := Entity.new(building.id)
	entity.add_component(building)
	return entity
