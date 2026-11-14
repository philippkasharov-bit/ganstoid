## Parked cars (V1): one every PARK_EVERY_M or so along the kerb of
## residential and arterial streets near the district, facing with traffic
## (right-hand side). Seeded, so a save rebuilds the same cars.
class_name VehicleSeeder
extends RefCounted

const PARK_EVERY_M := 18.0
const KEEP_SHARE := 0.45            # not every space is taken
const KERB_IN_M := 1.2              # car centre this far in from the kerb
const MAX_CARS := 450
const UNLOCKED_SHARE := 0.15
const MAX_DRIVEWAY_CARS := 180
const DRIVEWAY_SHARE := 0.4
const DRIVEWAY_IN_M := 2.8          # car centre this far past the apron, up the drive
const TIERS := ["res", "art"]
const COLORS := [Color(0.85, 0.85, 0.85), Color(0.15, 0.15, 0.17), Color(0.55, 0.57, 0.6), Color(0.6, 0.12, 0.12),
	Color(0.15, 0.25, 0.5), Color(0.9, 0.9, 0.95), Color(0.35, 0.4, 0.3), Color(0.75, 0.65, 0.45)]

static func seed(world: World, seed: int, city: CityData, centre: Vector2, radius: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var spots: Array = []   # [position, heading]
	for road in city.roads:
		if not TIERS.has(road["tier"]) or not road.has("w"):
			continue
		var pts: PackedVector2Array = road["pts"]
		for k in pts.size() - 1:
			_spots_along(spots, rng, pts[k], pts[k + 1], road["w"], centre, radius)
	var stride := maxf(1.0, float(spots.size()) / MAX_CARS)   # spread over the whole district, not the first streets listed
	var n := 0
	while n < MAX_CARS and int(n * stride) < spots.size():
		_park(world, rng, StringName("car_%d" % n), spots[int(n * stride)])
		n += 1
	return n + _driveways(world, rng, city, centre, radius)

## B5: a car up many driveways, nose to the house, as LA parks. Owned by the
## street like the kerb cars, so DriveSystem hands the one nearest a driver's
## home to that driver. Seeded after the kerb cars, so those stay the same.
static func _driveways(world: World, rng: RandomNumberGenerator, city: CityData, centre: Vector2, radius: float) -> int:
	var solid := CityCollision.new(city)
	var n := 0
	for d in city.driveways:
		if n >= MAX_DRIVEWAY_CARS or d["c"].distance_to(centre) > radius or rng.randf() >= DRIVEWAY_SHARE:
			continue
		var into: Vector2 = d["dir"]
		var at: Vector2 = d["c"] + into * (float(d["len"]) + DRIVEWAY_IN_M)
		if not solid.blocked(at, 1.2):
			_park(world, rng, StringName("car_d%d" % n), [at, into.angle()])
			n += 1
	return n

static func _spots_along(spots: Array, rng: RandomNumberGenerator, a: Vector2, b: Vector2, w: float, centre: Vector2, radius: float) -> void:
	var dir := (b - a).normalized()
	var right := Vector2(-dir.y, dir.x)
	var seg := a.distance_to(b)
	var t := PARK_EVERY_M * 0.5
	while t < seg - PARK_EVERY_M * 0.5:
		var p := a + dir * t + right * (w * 0.5 - KERB_IN_M)
		t += PARK_EVERY_M
		if p.distance_to(centre) <= radius and rng.randf() < KEEP_SHARE:
			spots.append([p, dir.angle()])

static func _park(world: World, rng: RandomNumberGenerator, id: StringName, spot: Array) -> void:
	var car := VehicleData.new()
	car.id = id
	car.position = spot[0]
	car.heading = spot[1]
	car.locked = rng.randf() > UNLOCKED_SHARE
	car.owner_id = &"street"
	car.color = COLORS[rng.randi() % COLORS.size()]
	var e := Entity.new(car.id)
	e.add_component(car)
	world.register_entity(e)
