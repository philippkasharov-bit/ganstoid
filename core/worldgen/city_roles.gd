## MG1a/R1: gives the REAL city's fixed buildings their sim roles (no geometry is
## generated). Each real footprint inside the active district becomes a
## BuildingData at its front door (metres). Roles are RESHUFFLED every new game
## (new seed) but always logical for what the building physically is:
##   house / apartments -> mostly homes; a few trap houses and safehouses
##   commercial         -> shops; a few laundromat-style fronts
##   industrial         -> workshops/warehouses (never retail shops), fronts, safehouses
##   garage             -> mostly safehouses and fronts, some workshops
## Every zone gets every role, in different proportions: DOWNTOWN (commercial
## area) is shop-heavy and clean, EDGE (industrial area / near underpasses and
## rail yards) hides most fronts and safehouses, SPRAWL is mostly homes.
## Civic buildings (schools, churches) get no sim role yet.
class_name CityRoles
extends RefCounted

const EDGE_DARK_SPOT_M := 150.0   # near an underpass / rail yard = low visibility = EDGE

const RES := GanstoidEnums.BuildingType.RESIDENCE
const BIZ := GanstoidEnums.BuildingType.LEGIT_BUSINESS
const FRONT := GanstoidEnums.BuildingType.ILLEGAL_FRONT
const SAFE := GanstoidEnums.BuildingType.SAFEHOUSE
const DOWNTOWN := GanstoidEnums.CityZone.DOWNTOWN
const SPRAWL := GanstoidEnums.CityZone.SPRAWL
const EDGE := GanstoidEnums.CityZone.EDGE

## kind -> zone -> role weights (normalized per table).
const ROLE_WEIGHTS := {
	"house": {DOWNTOWN: {RES: 97, FRONT: 2, SAFE: 1}, SPRAWL: {RES: 95, FRONT: 3, SAFE: 2}, EDGE: {RES: 86, FRONT: 8, SAFE: 6}},
	"apartments": {DOWNTOWN: {RES: 98, FRONT: 1, SAFE: 1}, SPRAWL: {RES: 96, FRONT: 2, SAFE: 2}, EDGE: {RES: 90, FRONT: 5, SAFE: 5}},
	"commercial": {DOWNTOWN: {BIZ: 95, FRONT: 5}, SPRAWL: {BIZ: 88, FRONT: 12}, EDGE: {BIZ: 75, FRONT: 25}},
	"industrial": {DOWNTOWN: {BIZ: 70, FRONT: 20, SAFE: 10}, SPRAWL: {BIZ: 60, FRONT: 25, SAFE: 15}, EDGE: {BIZ: 45, FRONT: 35, SAFE: 20}},
	"garage": {DOWNTOWN: {BIZ: 40, FRONT: 30, SAFE: 30}, SPRAWL: {BIZ: 25, FRONT: 35, SAFE: 40}, EDGE: {BIZ: 15, FRONT: 40, SAFE: 45}},
	"building": {DOWNTOWN: {RES: 30, BIZ: 65, FRONT: 4, SAFE: 1}, SPRAWL: {RES: 70, BIZ: 24, FRONT: 4, SAFE: 2}, EDGE: {RES: 35, BIZ: 25, FRONT: 28, SAFE: 12}},
}
## What kind of legit business each building kind can host ("no shops in industrial").
const BUSINESS_KIND := {"commercial": &"shop", "industrial": &"workshop", "garage": &"workshop", "building": &"shop"}

static func generate(world: World, seed: int, city: CityData, centre: Vector2, radius: float) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var areas := _areas_by_kind(city)
	var ids: Array[StringName] = []
	var made: Array = []   # [BuildingData, kind]
	for b in city.buildings:
		var door: Vector2 = b["door"]
		if door.distance_to(centre) > radius or b["kind"] == "civic":
			continue
		var building := _make(rng, b, _zone_at(door, areas, city))
		made.append([building, String(b["kind"])])
		var entity := Entity.new(building.id)
		entity.add_component(building)
		world.register_entity(entity)
		ids.append(building.id)
	_ensure_every_role(rng, made)
	return ids

## Small zones can miss a role by chance: convert one building that is allowed
## to hold it (weight > 0 for its kind and zone), so every zone has every role.
static func _ensure_every_role(rng: RandomNumberGenerator, made: Array) -> void:
	var have := {}
	for m in made:
		have[[m[0].zone, m[0].building_type]] = true
	for zone in GanstoidEnums.CityZone.values():
		for role in GanstoidEnums.BuildingType.values():
			if have.has([zone, role]):
				continue
			var options := made.filter(func(m: Array) -> bool:
				return m[0].zone == zone and m[0].building_type == RES and ROLE_WEIGHTS.get(m[1], ROLE_WEIGHTS["building"])[zone].get(role, 0) > 0)
			if options.is_empty():
				options = made.filter(func(m: Array) -> bool: return m[0].zone == zone and ROLE_WEIGHTS.get(m[1], ROLE_WEIGHTS["building"])[zone].get(role, 0) > 0)
			if options.is_empty():
				continue
			var pick: Array = options[rng.randi() % options.size()]
			_set_role(pick[0], role, pick[1])
			have[[zone, role]] = true

static func _make(rng: RandomNumberGenerator, b: Dictionary, zone: GanstoidEnums.CityZone) -> BuildingData:
	var building := BuildingData.new()
	building.id = b["id"]
	building.position = b["door"]
	building.zone = zone
	_set_role(building, _type_for(rng, String(b["kind"]), zone), String(b["kind"]), rng)
	return building

static func _set_role(building: BuildingData, role: GanstoidEnums.BuildingType, kind: String, rng: RandomNumberGenerator = null) -> void:
	building.building_type = role
	building.business_kind = BUSINESS_KIND.get(kind, &"shop") if role == BIZ else &""
	building.is_raidable = role in [FRONT, SAFE]
	var band: Vector2i = CityGenerator.REVENUE_BY_TYPE[role]
	building.daily_revenue = rng.randi_range(band.x, band.y) if rng != null else (band.x + band.y) / 2
	building.cash_on_hand = building.daily_revenue   # starts with one day's take banked

static func _type_for(rng: RandomNumberGenerator, kind: String, zone: GanstoidEnums.CityZone) -> GanstoidEnums.BuildingType:
	var weights: Dictionary = ROLE_WEIGHTS.get(kind, ROLE_WEIGHTS["building"])[zone]
	var total := 0
	for w in weights.values():
		total += w
	var roll := rng.randi_range(0, total - 1)
	for t in weights:
		roll -= weights[t]
		if roll < 0:
			return t
	return RES   # unreachable; satisfies the typed return

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
