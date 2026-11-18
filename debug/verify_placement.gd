## VS2B validator: the placement rules (Placement). Over three districts (the
## spawn, a downtown grid, a dense apartment area):
##   - no placed hydrant, mailbox or bin breaks a rule (carriageway, building,
##     driveway, ramp, crosswalk, hydrant, tree well, lamp, its neighbours)
##   - no parked car breaks a car rule (hydrant 4.6 m, crosswalk and ramp 6 m,
##     corner 6 m, driveway), nor sits within 0.5 m of the next car
##   - hydrants stand every 90-120 m or so along the kerbs (not only the map's 80)
## It prints what was placed, moved and refused per kind. Built twice, asked in
## a different order, the placements are identical, and so are the parked cars
## of two worlds made from the same seed.
extends SceneTree

const DISTRICTS := [Vector2(5165.2, 3371.5), Vector2(5600.0, 2700.0), Vector2(975.0, 2925.0)]
const RADIUS := 220.0
const SEED := 4242

func _initialize() -> void:
	var city := CityData.load_file()
	var t0 := Time.get_ticks_msec()
	var place := Placement.new()
	place._build(city)
	var built := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	place.near("mailbox", DISTRICTS[0], 240.0)   # a chunk's worth of driveway items, made on the first ask
	var items := Time.get_ticks_msec() - t0
	var fail := ""
	var broken := {}
	var counts := {}
	for c in DISTRICTS:
		for kind in ["hydrant", "mailbox", "bin"]:
			var got := place.near(kind, c, RADIUS)
			counts[kind] = int(counts.get(kind, 0)) + got.size()
			var others: Array = []
			if kind != "hydrant":
				for k2 in ["mailbox", "bin"]:
					for o in place.near(k2, c, RADIUS + 5.0):
						others.append([k2, o[0]])
			for it in got:
				for rule in place.violations(kind, it[0]) + Placement.conflicts(kind, it[0], others):
					broken["%s/%s" % [kind, rule]] = int(broken.get("%s/%s" % [kind, rule], 0)) + 1
	var hydrant_count := place.near("hydrant", Vector2(3000, 3000), 6000.0).size()
	if hydrant_count < 1000:
		fail = "only %d hydrants in the city" % hydrant_count
	if fail == "" and not broken.is_empty():
		fail = "rules broken: %s" % [broken]
	if fail == "":
		fail = _cars(city, place)
	if fail == "":
		fail = _same(city, place)
	print("PLACEMENT: built in %d ms, a district's driveway items in %d ms; %d hydrants in the city" % [built, items, hydrant_count])
	print("PLACEMENT: in the districts %s" % [counts])
	print("PLACEMENT: placed / moved / refused %s" % [place.stats])
	print("PLACEMENT_VERIFY: %s" % ("PASS" if fail == "" else "FAIL - " + fail))
	quit(0 if fail == "" else 1)

## Parked cars from VehicleSeeder in each district keep every car rule and their gaps.
func _cars(city: CityData, place: Placement) -> String:
	for c in DISTRICTS:
		var world := World.new()
		VehicleSeeder.seed(world, SEED, city, c, RADIUS)
		var kerb: Array[Vector2] = []
		for id in world.entities:
			if String(id).begins_with("car_") and not String(id).begins_with("car_d"):
				kerb.append((world.entities[id].get_component(ComponentNames.VEHICLE) as VehicleData).position)
		if kerb.size() < 10:
			return "only %d kerb cars round %s" % [kerb.size(), c]
		for p in kerb:
			var broke := place.violations("car", p, _road_under(city, p))
			if not broke.is_empty():
				return "a parked car at %s breaks %s" % [p, broke]
			for q in kerb:
				if q != p and q.distance_to(p) < Placement.CAR_GAP - 0.01:
					return "two parked cars nose to tail at %s" % p
		print("PLACEMENT: %d kerb cars round %s, all legal" % [kerb.size(), c])
	return ""

## The kerbed road whose carriageway holds `p` (a parked car's own road).
func _road_under(city: CityData, p: Vector2) -> int:
	var best := -1
	var near := INF
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		if not r["tier"] in Placement.KERBED:
			continue
		var pts: PackedVector2Array = r["pts"]
		for k in pts.size() - 1:
			var d := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1]).distance_to(p)
			if d < near:
				near = d
				best = i
	return best

## A second placement, asked in the other order, and a second world: the same result.
func _same(city: CityData, place: Placement) -> String:
	var other := Placement.new()
	other._build(city)
	var order := [DISTRICTS[2], DISTRICTS[0], DISTRICTS[1]]
	for c in order:
		for kind in ["bin", "hydrant", "mailbox"]:
			var a: Array = place.near(kind, c, RADIUS)
			var b: Array = other.near(kind, c, RADIUS)
			a.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			b.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			if str(a) != str(b):
				return "%s round %s differ between two builds" % [kind, c]
	var cars: Array[String] = []
	for n in 2:
		var world := World.new()
		VehicleSeeder.seed(world, SEED, city, DISTRICTS[0], RADIUS)
		var list: Array = []
		for id in world.entities:
			list.append("%s %s" % [id, (world.entities[id].get_component(ComponentNames.VEHICLE) as VehicleData).position])
		list.sort()
		cars.append(str(list))
	if cars[0] != cars[1]:
		return "two worlds from one seed park different cars"
	return ""
