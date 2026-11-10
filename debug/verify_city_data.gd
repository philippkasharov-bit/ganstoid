## City batch C1 validator: the frozen city loads, IDs are unique + namespaced,
## everything is inside the map, every tier/area exists, and NO street ends in
## mid-air: each street end touches another road, the map edge (= expansion),
## or is a listed dead end (real cul-de-sacs/alley ends from the source map).
## Trails, ramps and freeways are exempt.
extends SceneTree

const TOUCH_M := 12.0   # road ends must be within this of another road's centreline
const CELL := 64.0

func _initialize() -> void:
	var city := CityData.load_file()
	assert(city != null, "city loads")
	assert(city.roads.size() > 1200, "full road network present")
	var ids := {}
	for road in city.roads:
		assert(String(road["id"]).begins_with("base:"), "namespaced id")
		assert(not ids.has(road["id"]), "unique id %s" % road["id"])
		ids[road["id"]] = true
		assert(road["pts"].size() >= 2, "road has a line")
		for p in road["pts"]:
			assert(p.x >= -1 and p.y >= -1 and p.x <= city.size_m + 1 and p.y <= city.size_m + 1, "inside map")
	for tier in ["fwy", "art", "res", "alley"]:
		assert(city.roads_of(tier).size() > 0, "tier %s present" % tier)
	var kinds := {}
	for a in city.areas:
		kinds[a["kind"]] = true
	for k in ["industrial", "park", "commercial"]:
		assert(kinds.has(k), "area %s present" % k)
	var dangling := _dangling_ends(city)
	print("streets: %d, boulevards: %d, freeways: %d, cul-de-sacs: %d, dangling ends: %d" % [
		city.roads_of("res").size(), city.roads_of("art").size(), city.roads_of("fwy").size(), city.dead_ends.size(), dangling.size()])
	for p in dangling.slice(0, 10):
		print("  dangling at ", p)
	assert(dangling.is_empty(), "no street ends in mid-air")
	# C3: real buildings loaded, and no road runs through one (except freeways/ramps on overpasses)
	assert(city.buildings.size() > 1000, "buildings loaded")
	var col := CityCollision.new(city)
	var through := 0
	for road in city.roads:
		if road["tier"] in ["res", "alley", "art"]:
			var pts: PackedVector2Array = road["pts"]
			for k in pts.size() - 1:
				if col.blocked(pts[k].lerp(pts[k + 1], 0.5), 0.0):
					through += 1
	print("buildings: %d, road segments passing through a building: %d" % [city.buildings.size(), through])
	assert(through * 100 < city.roads.size(), "roads don't run through buildings (<1%: OSM tunnels/arcades)")
	print("CITY_DATA_VERIFY: PASS")
	quit()

func _dangling_ends(city: CityData) -> Array:
	var grid := {}
	for i in city.roads.size():
		var pts: PackedVector2Array = city.roads[i]["pts"]
		for j in pts.size() - 1:
			# register the segment in every cell it passes (long simplified segments span many cells)
			var steps := int(pts[j].distance_to(pts[j + 1]) / (CELL * 0.5)) + 1
			var seen := {}
			for k in steps + 1:
				var key := Vector2i((pts[j].lerp(pts[j + 1], float(k) / steps) / CELL).floor())
				if seen.has(key):
					continue
				seen[key] = true
				if not grid.has(key):
					grid[key] = []
				grid[key].append([pts[j], pts[j + 1], i])
	var out := []
	for i in city.roads.size():
		var road: Dictionary = city.roads[i]
		if road["tier"] in ["trail", "ramp", "fwy", "svc", "path", "aisle", "drive"]:   # lanes in lots end where they end
			continue
		var pts: PackedVector2Array = road["pts"]
		if pts[0] == pts[pts.size() - 1]:
			continue   # loop street: no ends to dangle
		for end in [pts[0], pts[pts.size() - 1]]:
			if not _connected(end, i, grid, city):
				out.append(end)
	return out

var _dead_grid := {}

func _dead_near(p: Vector2, city: CityData) -> Array:
	if _dead_grid.is_empty():
		for d in city.dead_ends:
			var key := Vector2i((d / CELL).floor())
			if not _dead_grid.has(key):
				_dead_grid[key] = []
			_dead_grid[key].append(d)
	var out := []
	var c := Vector2i((p / CELL).floor())
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			out.append_array(_dead_grid.get(c + Vector2i(dx, dy), []))
	return out

func _connected(p: Vector2, own: int, grid: Dictionary, city: CityData) -> bool:
	if p.x < TOUCH_M or p.y < TOUCH_M or p.x > city.size_m - TOUCH_M or p.y > city.size_m - TOUCH_M:
		return true   # map edge = future expansion connector
	for d in _dead_near(p, city):
		if d.distance_to(p) < TOUCH_M:
			return true   # listed dead end (cul-de-sac, alley end)
	var c := Vector2i((p / CELL).floor())
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for seg in grid.get(c + Vector2i(dx, dy), []):
				if seg[2] == own:
					continue
				if Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) < TOUCH_M:
					return true
	return false
