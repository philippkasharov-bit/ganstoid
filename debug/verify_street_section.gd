## MP2 validator: the street cross-section. Every street's sidewalk band splits
## into parkway + paving without losing or inventing width, LA has both kinds of
## street, and every feature on the band sits where it belongs: tree wells
## inside the band and never in a building or on a driveway, driveway cuts on
## the kerb line, kerb ramps at the ends of real crosswalks.
extends SceneTree

const SAMPLE := 800
const CELL := 50.0
const RAMP_REACH := 22.5      # street_section.py RAMP_REACH_M: crosswalk end (lot line) to its kerb
const MIN_DRIVE_LEN := 2.0   # street_section.py APRON_MIN_LEN: a shorter apron is dropped

var _grid := {}        # cell -> Array[[a, b, w, side]]
var _cross := {}       # cell -> PackedVector2Array of crosswalk end points

func _initialize() -> void:
	var city := CityData.load_file()
	if not _check(not city.tree_wells.is_empty() and not city.driveways.is_empty() and not city.kerb_ramps.is_empty(),
			"the section file is loaded (wells, driveways, ramps)"):
		return
	_build_grid(city)
	_build_crosswalks(city)
	if not _check_widths(city):
		return
	var col := CityCollision.new(city)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	if not _check_wells(city, col, rng):
		return
	if not _check_driveways(city, col, rng):
		return
	if not _check_ramps(city):
		return
	print("STREET_SECTION_VERIFY: PASS")
	quit()

## walk + park must be exactly the side width MP1 gave the road, and the paving
## must be wide enough to walk on. Both kinds of street must exist.
func _check_widths(city: CityData) -> bool:
	var bad := 0
	var with_park := 0
	var paved := 0
	var worst := ""
	for road in city.roads:
		var side: float = road.get("side", 0.0)
		if side <= 0.0:
			continue
		if not road.has("walk"):
			bad += 1
			worst = "road %s has no cross-section" % road["id"]
			continue
		var walk: float = road["walk"]
		var park: float = road["park"]
		if absf(walk + park - side) > 0.011 or walk < 1.2:
			bad += 1
			worst = "road %s: walk %.2f + park %.2f != side %.2f" % [road["id"], walk, park, side]
		if park > 0.0:
			with_park += 1
		else:
			paved += 1
	print("streets with a sidewalk: %d, of them parkway %d, paved kerb-to-lot %d" % [with_park + paved, with_park, paved])
	if not _check(bad == 0, "every sidewalk band splits into parkway + paving (%d bad, e.g. %s)" % [bad, worst]):
		return false
	return _check(with_park * 10 > paved and paved * 10 > with_park, "LA has both parkway streets and fully paved ones")

## A well must sit between the kerb and the lot line, out of every building, and
## clear of the driveways and ramps (a tree in a driveway is a bug, not a tree).
func _check_wells(city: CityData, col: CityCollision, rng: RandomNumberGenerator) -> bool:
	var feats := PackedVector2Array()
	for f in city.driveways + city.kerb_ramps:
		feats.append(f["c"])
	var off_band := 0
	var in_bld := 0
	var on_drive := 0
	for i in mini(SAMPLE, city.tree_wells.size()):
		var p: Vector2 = city.tree_wells[rng.randi() % city.tree_wells.size()]
		if not _in_some_band(p, 0.1):   # some street's band: alleys and parallel streets overlap
			off_band += 1
		if col.blocked(p, city.well_r):
			in_bld += 1
		for q in feats:
			if q.distance_to(p) < 2.0:
				on_drive += 1
				break
	print("tree wells %d: sampled %d, off the band %d, in a building %d, on a driveway/ramp %d" % [
		city.tree_wells.size(), mini(SAMPLE, city.tree_wells.size()), off_band, in_bld, on_drive])
	return _check(off_band == 0 and in_bld == 0 and on_drive == 0, "tree wells sit in the band, clear of buildings and driveways")

## A driveway cut starts on the kerb line of a street and crosses the whole band.
func _check_driveways(city: CityData, col: CityCollision, rng: RandomNumberGenerator) -> bool:
	var off_kerb := 0
	var in_bld := 0
	var short := 0
	for i in mini(SAMPLE, city.driveways.size()):
		var d: Dictionary = city.driveways[rng.randi() % city.driveways.size()]
		var side := _kerb_side(d["c"], 0.7)
		if side < 0.0:
			off_kerb += 1
		elif float(d["len"]) < minf(side + 0.5, MIN_DRIVE_LEN):
			short += 1
		if col.blocked(d["c"], 0.0):
			in_bld += 1
	print("driveway cuts %d: sampled %d, off the kerb line %d, not crossing the band %d, in a building %d" % [
		city.driveways.size(), mini(SAMPLE, city.driveways.size()), off_kerb, short, in_bld])
	return _check(off_kerb == 0 and short == 0 and in_bld == 0, "driveway cuts start on the kerb and cross the band")

## Every kerb ramp belongs to a crosswalk end (that is where LA builds them).
func _check_ramps(city: CityData) -> bool:
	var orphan := 0
	var off_kerb := 0
	for r in city.kerb_ramps:
		if not _near_crosswalk_end(r["c"]):
			orphan += 1
		if _kerb_side(r["c"], 0.7) < 0.0:
			off_kerb += 1
	print("kerb ramps %d, not at a crosswalk end: %d, off the kerb line: %d" % [city.kerb_ramps.size(), orphan, off_kerb])
	return _check(orphan == 0 and off_kerb == 0, "every kerb ramp sits on the kerb at a crosswalk end")

## True if p lies between the kerb and the lot line of any street near it.
func _in_some_band(p: Vector2, slack: float) -> bool:
	var key := Vector2i(int(p.x / CELL), int(p.y / CELL))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for seg in _grid.get(key + Vector2i(dx, dy), []):
				var d := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p)
				if d >= seg[2] * 0.5 - slack and d <= seg[2] * 0.5 + seg[3] + slack:
					return true
	return false

## Side width of a street whose kerb line passes within `tol` of p, else -1.
func _kerb_side(p: Vector2, tol: float) -> float:
	var key := Vector2i(int(p.x / CELL), int(p.y / CELL))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for seg in _grid.get(key + Vector2i(dx, dy), []):
				var d := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p)
				if absf(d - seg[2] * 0.5) <= tol:
					return seg[3]
	return -1.0

func _near_crosswalk_end(p: Vector2) -> bool:
	var key := Vector2i(int(p.x / CELL), int(p.y / CELL))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for q in _cross.get(key + Vector2i(dx, dy), PackedVector2Array()):
				if q.distance_to(p) < RAMP_REACH:
					return true
	return false

func _build_grid(city: CityData) -> void:
	for road in city.roads:
		if float(road.get("side", 0.0)) <= 0.0:
			continue
		var w: float = road["w"]
		var side: float = road["side"]
		var pts: PackedVector2Array = road["pts"]
		for i in pts.size() - 1:
			var seg := [pts[i], pts[i + 1], w, side]
			var r := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(w * 0.5 + side + 2.0)
			for x in range(int(r.position.x / CELL), int(r.end.x / CELL) + 1):
				for y in range(int(r.position.y / CELL), int(r.end.y / CELL) + 1):
					var key := Vector2i(x, y)
					if not _grid.has(key):
						_grid[key] = []
					_grid[key].append(seg)

func _build_crosswalks(city: CityData) -> void:
	for c in city.crosswalks:
		var d: Vector2 = c["dir"]
		var along := Vector2(-d.y, d.x) * (float(c["len"]) * 0.5)
		for end in [c["c"] - along, c["c"] + along]:
			var key := Vector2i(int(end.x / CELL), int(end.y / CELL))
			if not _cross.has(key):
				_cross[key] = PackedVector2Array()
			_cross[key].append(end)

## Fails loudly and exits (an assert would freeze a headless run in the debugger).
func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("STREET_SECTION_VERIFY: FAIL - ", what)
		quit(1)
	return ok
