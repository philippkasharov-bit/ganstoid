## MG1a: gives the REAL city's fixed buildings their sim roles (no geometry is generated).
## Each real footprint inside the active district becomes a BuildingData whose
## position is its front door (metres). Type comes from what the building is
## (house/apartments = homes, shops = businesses, industrial/garages = where
## fronts and safehouses hide); zone comes from where it stands (commercial area
## = DOWNTOWN, industrial area or near a dark spot = EDGE, else SPRAWL).
## Civic buildings (schools, churches) get no sim role yet. Seeded: same seed
## and district -> same city.
class_name CityRoles
extends RefCounted

const EDGE_DARK_SPOT_M := 150.0   # near an underpass / rail yard = low visibility = EDGE

## Weights for buildings whose OSM kind doesn't fix their role (normalized per table).
const KIND_WEIGHTS := {
	"industrial": {GanstoidEnums.BuildingType.LEGIT_BUSINESS: 45, GanstoidEnums.BuildingType.ILLEGAL_FRONT: 40, GanstoidEnums.BuildingType.SAFEHOUSE: 15},
	"garage": {GanstoidEnums.BuildingType.LEGIT_BUSINESS: 30, GanstoidEnums.BuildingType.ILLEGAL_FRONT: 40, GanstoidEnums.BuildingType.SAFEHOUSE: 30},
}
const FIXED_KIND := {
	"house": GanstoidEnums.BuildingType.RESIDENCE,
	"apartments": GanstoidEnums.BuildingType.RESIDENCE,
	"commercial": GanstoidEnums.BuildingType.LEGIT_BUSINESS,
}

static func generate(world: World, seed: int, city: CityData, centre: Vector2, radius: float) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var areas := _areas_by_kind(city)
	var ids: Array[StringName] = []
	for b in city.buildings:
		var door: Vector2 = b["door"]
		if door.distance_to(centre) > radius or b["kind"] == "civic":
			continue
		var building := _make(rng, b, _zone_at(door, areas, city))
		var entity := Entity.new(building.id)
		entity.add_component(building)
		world.register_entity(entity)
		ids.append(building.id)
	return ids

static func _make(rng: RandomNumberGenerator, b: Dictionary, zone: GanstoidEnums.CityZone) -> BuildingData:
	var building := BuildingData.new()
	building.id = b["id"]
	building.position = b["door"]
	building.zone = zone
	building.building_type = _type_for(rng, String(b["kind"]), zone)
	building.is_raidable = building.building_type in [GanstoidEnums.BuildingType.ILLEGAL_FRONT, GanstoidEnums.BuildingType.SAFEHOUSE]
	var band: Vector2i = CityGenerator.REVENUE_BY_TYPE[building.building_type]
	building.daily_revenue = rng.randi_range(band.x, band.y)
	building.cash_on_hand = building.daily_revenue   # starts with one day's take banked
	return building

static func _type_for(rng: RandomNumberGenerator, kind: String, zone: GanstoidEnums.CityZone) -> GanstoidEnums.BuildingType:
	if FIXED_KIND.has(kind):
		return FIXED_KIND[kind]
	var weights: Dictionary = KIND_WEIGHTS.get(kind, CityGenerator.ZONE_WEIGHTS[zone])
	var total := 0
	for w in weights.values():
		total += w
	var roll := rng.randi_range(0, total - 1)
	for t in weights:
		roll -= weights[t]
		if roll < 0:
			return t
	return GanstoidEnums.BuildingType.RESIDENCE   # unreachable; satisfies the typed return

static func _zone_at(p: Vector2, areas: Dictionary, city: CityData) -> GanstoidEnums.CityZone:
	for poly in areas.get("commercial", []):
		if Geometry2D.is_point_in_polygon(p, poly):
			return GanstoidEnums.CityZone.DOWNTOWN
	for poly in areas.get("industrial", []):
		if Geometry2D.is_point_in_polygon(p, poly):
			return GanstoidEnums.CityZone.EDGE
	for d in city.dark_spots:
		if d.distance_to(p) < EDGE_DARK_SPOT_M:
			return GanstoidEnums.CityZone.EDGE
	return GanstoidEnums.CityZone.SPRAWL

static func _areas_by_kind(city: CityData) -> Dictionary:
	var out := {}
	for a in city.areas:
		if not out.has(a["kind"]):
			out[a["kind"]] = []
		out[a["kind"]].append(a["poly"])
	return out
