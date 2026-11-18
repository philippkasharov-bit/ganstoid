## VS2A validator: the kerb runs (KerbRuns), sampled in three districts (the
## spawn, a downtown grid and a dense apartment area):
##   - one run is one connected line: no piece longer than a road segment can
##     make, no fold back on itself (an overlap)
##   - no kerb inside another street's carriageway, except where it is dropped
##     (a driveway, a lot entrance, a ramp), and almost none inside a building
##   - every run end is explained (a rounded return, a corner, a carry-on, a
##     road end), and a return or carry-on that has a partner (the other
##     street is kerbed) meets another run's end within 5 cm
##   - the kerb is full height everywhere except in drops and their flares
##   - driveways, ramps and meters are actually used, and kerbs by hydrants are red
##   - every flat street layer has its own height (StreetLevels)
## Also: a chunk build draws each run once (the chunk of its first point).
extends SceneTree

const DISTRICTS := [Vector2(5165.2, 3371.5), Vector2(5600.0, 2700.0), Vector2(975.0, 2925.0)]
const RADIUS := 220.0
const END_REASONS := ["junction", "corner", "continuation", "road_end"]
const MEET_M := 0.05
const MATCH_MIN := 0.85   # share of returns and carry-ons that must find their partner

func _initialize() -> void:
	var city := CityData.load_file()
	var real := CityReal.load_files()
	var fail := _levels()
	var stats := {"runs": 0, "pieces": 0, "ramps": 0, "drops": 0, "red": 0, "meters": 0, "in_road": 0, "in_building": 0, "checked": 0}
	var reasons := {}
	for c in DISTRICTS:
		if fail != "":
			break
		var runs := KerbRuns.build(city, real, c, RADIUS)
		fail = _check(city, runs, c, stats, reasons)
	if fail == "":
		fail = _used(city, real, stats)
	if fail == "":
		fail = _chunks(city, real)
	print("KERBS: %s" % [stats])
	print("KERBS: ends %s" % [reasons])
	print("KERBS_VERIFY: %s" % ("PASS" if fail == "" else "FAIL - " + fail))
	quit(0 if fail == "" else 1)

## The flat layers are all at different heights, lowest first.
func _levels() -> String:
	var order: Array = StreetLevels.ORDER
	for i in order.size() - 1:
		if float(order[i + 1]) <= float(order[i]):
			return "street layers %d and %d share a height or are out of order" % [i, i + 1]
	return ""

func _check(city: CityData, runs: Array[Dictionary], centre: Vector2, stats: Dictionary, reasons: Dictionary) -> String:
	if runs.size() < 40:
		return "only %d kerb runs round %s" % [runs.size(), centre]
	var ends: Array = []   # [point, reason, run index, which end]
	var streets := _street_grid(city, centre)
	var homes := _building_grid(city, centre)
	for ri in runs.size():
		var run: Dictionary = runs[ri]
		var pts: PackedVector2Array = run["pts"]
		var h: PackedFloat32Array = run["h"]
		var zone: PackedByteArray = run["zone"]
		stats["runs"] += 1
		stats["pieces"] += pts.size() - 1
		stats["ramps"] += run["ramps"].size()
		stats["meters"] += run["meters"].size()
		if h.size() != pts.size() or zone.size() != pts.size() or run["red"].size() != pts.size() - 1:
			return "run %d: heights, zones or colours do not match its points" % ri
		for k in pts.size() - 1:
			var step := pts[k].distance_to(pts[k + 1])
			if step > 900.0:
				return "run %d has a %.0f m piece" % [ri, step]
			if k > 0 and step > 0.05 and pts[k - 1].distance_to(pts[k]) > 0.05 and (pts[k] - pts[k - 1]).normalized().dot((pts[k + 1] - pts[k]).normalized()) < -0.5:
				return "run %d folds back on itself at %s" % [ri, pts[k]]
			stats["red"] += run["red"][k]
		for k in pts.size():
			if zone[k] == 0 and absf(h[k] - StreetLevels.KERB) > 0.001:
				return "run %d is not full height at %s outside any drop (%.3f)" % [ri, pts[k], h[k]]
			if h[k] < StreetLevels.KERB - 0.001:
				stats["drops"] += 1
				continue
			stats["checked"] += 1
			if _in_street(streets, pts[k], int(run["road"])):
				stats["in_road"] += 1
			if _in_building(homes, pts[k]):
				stats["in_building"] += 1
		for e in 2:
			var why: String = run["ends"][e]
			if not why in END_REASONS:
				return "run %d end %d has no reason (%s)" % [ri, e, why]
			reasons[why] = int(reasons.get(why, 0)) + 1
			ends.append([pts[0] if e == 0 else pts[pts.size() - 1], why, ri, bool(run["partner"][e])])
	if stats["in_road"] > 0:
		return "%d kerb points inside another street's carriageway round %s" % [stats["in_road"], centre]
	if float(stats["in_building"]) > 0.01 * float(stats["checked"]):
		return "%d of %d kerb points inside a building round %s" % [stats["in_building"], stats["checked"], centre]
	# returns and carry-ons meet a partner's end
	var wanted := 0
	var met := 0
	for a in ends:
		if not a[3]:
			continue
		var pa: Vector2 = a[0]
		if pa.distance_to(centre) > RADIUS - 30.0:
			continue   # its partner may belong to a road outside the sample
		wanted += 1
		for b in ends:
			if b[2] != a[2] and pa.distance_to(b[0]) < MEET_M:
				met += 1
				break
	if wanted > 0 and float(met) / wanted < MATCH_MIN:
		return "only %d of %d returns and carry-ons meet another run's end round %s" % [met, wanted, centre]
	print("KERBS: round %s: %d runs, %d of %d returns and carry-ons meet a partner" % [centre, runs.size(), met, wanted])
	return ""

## Every street's carriageway segments near `centre`, by 24 m cell.
func _street_grid(city: CityData, centre: Vector2) -> Dictionary:
	var grid := {}
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		if not r["tier"] in KerbRuns.STREET:
			continue
		var pts: PackedVector2Array = r["pts"]
		var half := KerbRuns.half_of(r)
		for k in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(centre, pts[k], pts[k + 1]).distance_to(centre) > RADIUS + 60.0:
				continue
			var lo := Vector2i(((pts[k].min(pts[k + 1]) - Vector2.ONE * half) / 24.0).floor())
			var hi := Vector2i(((pts[k].max(pts[k + 1]) + Vector2.ONE * half) / 24.0).floor())
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					grid.get_or_add(Vector2i(x, y), []).append([pts[k], pts[k + 1], half, i])
	return grid

## Inside another street, more than 5 cm in from its edge (a road running nearly along the kerb is its own road's neighbour lane, not a crossing).
func _in_street(grid: Dictionary, p: Vector2, own: int) -> bool:
	for s in grid.get(Vector2i((p / 24.0).floor()), []):
		if s[3] != own and Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p) < float(s[2]) - 0.05:
			return true
	return false

func _building_grid(city: CityData, centre: Vector2) -> Dictionary:
	var grid := {}
	for b in city.buildings:
		var poly: PackedVector2Array = b["poly"]
		if poly[0].distance_to(centre) > RADIUS + 100.0:
			continue
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		for x in range(int(floor(lo.x / 24.0)), int(floor(hi.x / 24.0)) + 1):
			for y in range(int(floor(lo.y / 24.0)), int(floor(hi.y / 24.0)) + 1):
				grid.get_or_add(Vector2i(x, y), []).append(poly)
	return grid

func _in_building(grid: Dictionary, p: Vector2) -> bool:
	for poly in grid.get(Vector2i((p / 24.0).floor()), []):
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false

## Drops, ramps and meters show up in the districts; red kerb shows up round the
## mapped hydrants (the city data has few, none in the districts above).
func _used(city: CityData, real: CityReal, stats: Dictionary) -> String:
	for key in ["drops", "ramps", "meters"]:
		if int(stats[key]) == 0:
			return "no %s anywhere in the districts" % key
	var tried := 0
	var red := 0
	for p in real.points:
		if p["kind"] != "hydrant" or tried >= 12:
			continue
		tried += 1
		for run in KerbRuns.build(city, real, p["p"], 40.0):
			for r in run["red"]:
				red += r
	print("KERBS: %d red kerb pieces round %d hydrants" % [red, tried])
	if tried > 0 and red == 0:
		return "no red kerb round %d hydrants" % tried
	return ""

## Two neighbouring chunk builds round the spawn: every run is drawn by exactly one of
## them. The game builds a chunk from its slice of the data (ChunkIndex3D); a slice must
## lead back to the whole city, or kerbs miss ramps and crossings past the chunk edge.
func _chunks(city: CityData, real: CityReal) -> String:
	var origin := Vector2(5165.2, 3371.5)
	var index := ChunkIndex3D.build(city, real, origin)
	for key in [Vector2i(0, 0), Vector2i(9, 9)]:   # one with data, one empty
		var sl: Array = index.slice(key)
		if sl[0].get_meta("whole", null) != city or sl[1].get_meta("whole", null) != real:
			return "chunk %s's slice does not lead back to the whole city" % key
	var all := KerbRuns.build(city, real, origin + Vector2(80, 80), 260.0)
	var firsts := {}
	for k in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var rect := Rect2(origin + Vector2(k) * CityMesh3D.CHUNK_M, Vector2.ONE * CityMesh3D.CHUNK_M)
		var keep := func(p: Vector2) -> bool: return Vector2i(((p - origin) / CityMesh3D.CHUNK_M).floor()) == k
		for run in KerbRuns.build(city, real, rect.get_center(), StreetDetail3D.OWN_REACH, keep):
			var key := "%d|%d|%s" % [run["road"], int(run["side"]), run["pts"][0]]
			if firsts.has(key):
				return "a run is drawn by two chunks (%s)" % key
			firsts[key] = true
	var missing := 0
	for run in all:
		var p: Vector2 = run["pts"][0]
		var k := Vector2i(((p - origin) / CityMesh3D.CHUNK_M).floor())
		if k.x in [0, 1] and k.y in [0, 1] and not firsts.has("%d|%d|%s" % [run["road"], int(run["side"]), p]):
			missing += 1
	if missing > 0:
		return "%d runs that start in the four chunks are drawn by none of them" % missing
	print("KERBS: four chunk builds draw %d runs, each once" % firsts.size())
	return ""
