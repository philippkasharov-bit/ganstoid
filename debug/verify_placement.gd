## VS2B validator: the placement rules (Placement). Over three districts (the
## spawn, a downtown grid, a dense apartment area):
##   - no placed hydrant, mailbox or bin breaks a rule (carriageway, building,
##     driveway, ramp, crosswalk, hydrant, tree well, lamp, its neighbours)
##   - no parked car breaks a car rule (hydrant 4.6 m, crosswalk and ramp 6 m,
##     corner 6 m, driveway), nor sits within 0.5 m of the next car
##   - hydrants stand every 90-120 m or so along the kerbs (not only the map's 80)
##   - B2: power poles break no rule (driveways, lamps, hydrants, ramps), and
##     mailboxes and bins keep clear of them and of lamps too; it counts the
##     palms left out by a driveway, pole, lamp or street corner
##   - B3: every piece of every designed group (stoops, bus stops, corner
##     stores, dumpsters...) keeps its rules; groups per template are printed
## It prints what was placed, moved and refused per kind. Built twice, asked in
## a different order, the placements are identical, and so are the parked cars
## of two worlds made from the same seed.
extends SceneTree

const DISTRICTS := [Vector2(5165.2, 3371.5), Vector2(5600.0, 2700.0), Vector2(975.0, 2925.0)]
const RADIUS := 220.0
const SEED := 4242

func _initialize() -> void:
	var city := CityData.load_file()
	StreetLights.install(city, city.spawn, 6500.0)   # as the game does: poles, trees and signs keep clear of lamps
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
	var b2 := _b2(city, place, broken)
	t0 = Time.get_ticks_msec()
	var groups := Clusters.of(place)
	var anchors := Time.get_ticks_msec() - t0
	var pieces := _b3(place, groups, broken)
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
	print("PLACEMENT: in the districts %s; %s" % [counts, b2])
	print("PLACEMENT: clusters (anchors found in %d ms) %s; pieces in the districts %s" % [anchors, groups.counts(), pieces])
	print("PLACEMENT: placed / moved / refused %s" % [place.stats])
	print("PLACEMENT_VERIFY: %s" % ("PASS" if fail == "" else "FAIL - " + fail))
	quit(0 if fail == "" else 1)

## B2: poles break no rule; palms and street trees that would are left out (counted).
func _b2(city: CityData, place: Placement, broken: Dictionary) -> Dictionary:
	var out := {"poles": 0, "palms kept": 0, "palms left out": 0}
	for c in DISTRICTS:
		for i in city.roads.size():
			var r: Dictionary = city.roads[i]
			if r["tier"] != "res" or not KerbRuns._seg_near(r["pts"], c, RADIUS):
				continue
			for q in place.poles_of(i):
				out["poles"] += 1
				for rule in place.violations("pole", q[0]):
					broken["pole/" + rule] = int(broken.get("pole/" + rule, 0)) + 1
		for w in city.tree_wells:
			if w.distance_to(c) < RADIUS:
				out["palms kept" if not place.find("palm", place.space.clear(w, 0.8)).is_empty() else "palms left out"] += 1
	if out["poles"] == 0:
		broken["no poles"] = 1
	return out

## B3: every cluster piece in the districts keeps its rules (and clear of mailboxes and bins).
func _b3(place: Placement, groups: Clusters, broken: Dictionary) -> Dictionary:
	var out := {}
	for c in DISTRICTS:
		var items: Array = []
		for k2 in ["mailbox", "bin"]:
			for o in place.near(k2, c, RADIUS + 15.0):
				items.append([k2, o[0]])
		for it in groups.near(c, RADIUS):
			out[it[0]] = int(out.get(it[0], 0)) + 1
			var kind: String = "tall_prop" if it[1] in Clusters.TALL else "prop"
			for rule in place.violations(kind, it[2]) + Placement.conflicts(kind, it[2], items):
				broken["%s/%s" % [it[1], rule]] = int(broken.get("%s/%s" % [it[1], rule], 0)) + 1
	if out.is_empty():
		broken["no clusters in the districts"] = 1
	return out

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
	var other_groups := Clusters.new()
	other_groups.place = other
	other_groups._anchors()
	for c in order:
		var a: Array = Clusters.of(place).near(c, RADIUS)
		var b: Array = other_groups.near(c, RADIUS)
		a.sort_custom(func(x: Array, y: Array) -> bool: return x[2] < y[2])
		b.sort_custom(func(x: Array, y: Array) -> bool: return x[2] < y[2])
		if str(a) != str(b):
			return "clusters round %s differ between two builds" % c
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
