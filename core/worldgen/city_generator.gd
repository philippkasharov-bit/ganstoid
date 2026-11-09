## Procedural city layout: an irregular-boundary "Sprawl (LA-ish)" city with
## TWO commercial hubs (a primary downtown + a smaller secondary node, both
## off-center and randomized per seed) instead of one perfectly centered
## bullseye, a major/minor street hierarchy instead of one uniform block
## size, and a rounded/organic city limit instead of a cropped square --
## the first version read as "generated" precisely because it had none of
## those three things. Seeded for determinism (same seed -> same city,
## required for Phase 6 save/load + testability). Produces only BuildingData
## entities — NPC population is PopulationSeeder's job, kept separate so
## either can be re-run/tuned independently. PopulationSeeder needs no
## zone-awareness of its own: it already assigns homes/jobs by picking
## randomly among all RESIDENCE/LEGIT_BUSINESS buildings, so once those
## buildings cluster by zone here, population naturally follows.
class_name CityGenerator
extends RefCounted

const LOT_SPACING := 32.0  # pixels between adjacent lots, tunable per art scale

## Minor block/street rhythm: BLOCK_SIZE lots, then a STREET_WIDTH gap.
## Every MAJOR_STREET_EVERY-th block boundary widens to MAJOR_STREET_WIDTH
## instead -- a thin hierarchy of ordinary streets vs. a few wider arterials
## cutting through, rather than one uniform grid spacing everywhere.
const BLOCK_SIZE := 4
const STREET_WIDTH := 1
const MAJOR_STREET_WIDTH := 2
const MAJOR_STREET_EVERY := 3

## Commercial-hub radii, as a fraction of grid_width. Primary = downtown
## proper. Secondary = a smaller satellite commercial node (a "strip" away
## from downtown) -- real sprawl has more than one place business clusters.
## Both hub LOCATIONS are randomized per seed (see _random_hub), not fixed
## at the grid center -- a single dead-centered hub is exactly what read as
## artificial/concentric in the first version.
const CORE_FRACTION := 0.12
const SECONDARY_CORE_FRACTION := 0.07
const EDGE_FRACTION := 0.42
const PRIMARY_HUB_OFFSET_MIN := 0.0
const PRIMARY_HUB_OFFSET_MAX := 0.3
const SECONDARY_HUB_OFFSET_MIN := 0.45
const SECONDARY_HUB_OFFSET_MAX := 0.8

## City limits are NOT the grid's square edge. BOUNDARY_SAMPLES angular
## control points, each scaling the base radius by a random multiplier,
## linearly interpolated between neighbors -- an organic, slightly
## irregular city outline instead of a cropped square, generated once per
## seed and reused for every lot's in/out test.
const BOUNDARY_SAMPLES := 12
const BOUNDARY_MIN_MULT := 0.72
const BOUNDARY_MAX_MULT := 1.18

## Per-zone weighted building-type distribution. Weights, not percentages —
## normalized internally per table, so they don't need to sum to 1.0.
## Downtown: business-heavy, almost no illegal fronts (too much foot
## traffic/visibility) -- applies at BOTH hubs. Sprawl: residence-heavy with
## everyday businesses mixed in, illegal activity present but minority.
## Edge: where illegal fronts and safehouses actually cluster -- low
## visibility, low rent, far from either hub and near the city limits.
const ZONE_WEIGHTS := {
	GanstoidEnums.CityZone.DOWNTOWN: {
		GanstoidEnums.BuildingType.RESIDENCE: 25,
		GanstoidEnums.BuildingType.LEGIT_BUSINESS: 70,
		GanstoidEnums.BuildingType.ILLEGAL_FRONT: 0,
		GanstoidEnums.BuildingType.SAFEHOUSE: 5,
	},
	GanstoidEnums.CityZone.SPRAWL: {
		GanstoidEnums.BuildingType.RESIDENCE: 70,
		GanstoidEnums.BuildingType.LEGIT_BUSINESS: 25,
		GanstoidEnums.BuildingType.ILLEGAL_FRONT: 4,
		GanstoidEnums.BuildingType.SAFEHOUSE: 1,
	},
	GanstoidEnums.CityZone.EDGE: {
		GanstoidEnums.BuildingType.RESIDENCE: 30,
		GanstoidEnums.BuildingType.LEGIT_BUSINESS: 15,
		GanstoidEnums.BuildingType.ILLEGAL_FRONT: 40,
		GanstoidEnums.BuildingType.SAFEHOUSE: 15,
	},
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
	var center := Vector2(grid_width - 1, grid_height - 1) / 2.0
	var base_radius := float(min(grid_width, grid_height)) / 2.0

	var boundary_mults := _build_boundary(rng)
	var primary_hub := _random_hub(rng, center, base_radius, PRIMARY_HUB_OFFSET_MIN, PRIMARY_HUB_OFFSET_MAX)
	var secondary_hub := _random_hub(rng, center, base_radius, SECONDARY_HUB_OFFSET_MIN, SECONDARY_HUB_OFFSET_MAX)

	var street_lookup_x := _build_street_lookup(grid_width)
	var street_lookup_y := _build_street_lookup(grid_height)

	var building_ids: Array[StringName] = []
	for y in grid_height:
		for x in grid_width:
			if street_lookup_x[x] or street_lookup_y[y]:
				continue  # minor or major street gap -- leave it empty, that gap IS the road
			var pos := Vector2(x, y)
			if not _inside_city(pos, center, base_radius, boundary_mults):
				continue  # outside the irregular city limits -- empty lot, not a building
			var zone := _zone_at(pos, primary_hub, secondary_hub, grid_width)
			var building := _build_at_lot(rng, x, y, zone)
			world.register_entity(_wrap_entity(building))
			building_ids.append(building.id)
	return building_ids

## True/false per lot-index along one axis: false = buildable lot,
## true = street gap. Reused identically for both axes since the block
## rhythm is the same either direction -- a lot is a street if EITHER axis
## says so (checked by the caller), which is what makes streets cross.
static func _build_street_lookup(size: int) -> Array[bool]:
	var lookup: Array[bool] = []
	lookup.resize(size)
	var i := 0
	var block_index := 0
	while i < size:
		for _b in BLOCK_SIZE:
			if i >= size:
				break
			lookup[i] = false
			i += 1
		var is_major := (block_index % MAJOR_STREET_EVERY) == (MAJOR_STREET_EVERY - 1)
		var gap: int = MAJOR_STREET_WIDTH if is_major else STREET_WIDTH
		for _g in gap:
			if i >= size:
				break
			lookup[i] = true
			i += 1
		block_index += 1
	return lookup

## A commercial hub's location, seeded and offset from the grid center by a
## random angle and a distance between min_frac/max_frac of base_radius --
## deliberately NOT the exact center, so downtown isn't a perfect bullseye.
static func _random_hub(rng: RandomNumberGenerator, center: Vector2, base_radius: float, min_frac: float, max_frac: float) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var dist := base_radius * rng.randf_range(min_frac, max_frac)
	return center + Vector2(cos(angle), sin(angle)) * dist

static func _build_boundary(rng: RandomNumberGenerator) -> Array[float]:
	var mults: Array[float] = []
	for i in BOUNDARY_SAMPLES:
		mults.append(rng.randf_range(BOUNDARY_MIN_MULT, BOUNDARY_MAX_MULT))
	return mults

## Interpolates between the two nearest angular boundary samples around pos
## to get a smooth (not jagged-random) irregular outline, then compares
## pos's actual distance from center against that interpolated radius.
static func _inside_city(pos: Vector2, center: Vector2, base_radius: float, mults: Array[float]) -> bool:
	var offset := pos - center
	var dist := offset.length()
	if dist <= 0.001:
		return true  # the center lot itself; angle is undefined, always in-city
	var angle := fposmod(offset.angle(), TAU)
	var slot := angle / TAU * BOUNDARY_SAMPLES
	var i0 := int(floor(slot)) % BOUNDARY_SAMPLES
	var i1 := (i0 + 1) % BOUNDARY_SAMPLES
	var t: float = slot - floor(slot)
	var mult: float = lerp(mults[i0], mults[i1], t)
	return dist <= base_radius * mult

## DOWNTOWN if close enough to EITHER hub (two separate commercial clusters
## render identically -- the point is two clusters exist, not that they're
## visually distinguished from each other). EDGE only once far from BOTH
## hubs, which also tends to mean "near the irregular city limits," same as
## a real city's rougher outskirts.
static func _zone_at(pos: Vector2, primary_hub: Vector2, secondary_hub: Vector2, grid_width: int) -> GanstoidEnums.CityZone:
	var core_radius := grid_width * CORE_FRACTION
	var secondary_core_radius := grid_width * SECONDARY_CORE_FRACTION
	var edge_radius := grid_width * EDGE_FRACTION
	var d_primary := pos.distance_to(primary_hub)
	var d_secondary := pos.distance_to(secondary_hub)
	if d_primary <= core_radius or d_secondary <= secondary_core_radius:
		return GanstoidEnums.CityZone.DOWNTOWN
	if d_primary >= edge_radius and d_secondary >= edge_radius:
		return GanstoidEnums.CityZone.EDGE
	return GanstoidEnums.CityZone.SPRAWL

static func _build_at_lot(rng: RandomNumberGenerator, x: int, y: int, zone: GanstoidEnums.CityZone) -> BuildingData:
	var building := BuildingData.new()
	building.id = StringName("bldg_%d_%d" % [x, y])
	building.position = Vector2(x * LOT_SPACING, y * LOT_SPACING)
	building.zone = zone
	building.building_type = _weighted_pick_type(rng, zone)
	building.is_raidable = building.building_type in [
		GanstoidEnums.BuildingType.ILLEGAL_FRONT,
		GanstoidEnums.BuildingType.SAFEHOUSE,
	]
	var band: Vector2i = REVENUE_BY_TYPE[building.building_type]
	building.daily_revenue = rng.randi_range(band.x, band.y)
	building.cash_on_hand = building.daily_revenue  # starts with one day's take banked
	return building

static func _weighted_pick_type(rng: RandomNumberGenerator, zone: GanstoidEnums.CityZone) -> GanstoidEnums.BuildingType:
	var weights: Dictionary = ZONE_WEIGHTS[zone]
	var total := 0
	for weight in weights.values():
		total += weight
	var roll := rng.randi_range(0, total - 1)
	var cumulative := 0
	for building_type in weights:
		cumulative += weights[building_type]
		if roll < cumulative:
			return building_type
	return GanstoidEnums.BuildingType.RESIDENCE  # unreachable; satisfies static type return

static func _wrap_entity(building: BuildingData) -> Entity:
	var entity := Entity.new(building.id)
	entity.add_component(building)
	return entity
