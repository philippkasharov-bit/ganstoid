## VS2B: the one place that decides whether a thing may stand somewhere on the
## street. Built once per city (a lock: chunks build on worker threads). It
## knows the fixed street (RoadSpace carriageways, buildings, driveway aprons,
## crosswalks, kerb ramps, tree wells, lamps) and the things it placed itself,
## in a fixed order, big before small:
##   1. hydrants: the map's own, plus one every 90-120 m along both kerbs of
##      every kerbed street (the map has only 80)
##   2. driveway items: a mailbox and the household's bins beside a driveway
##      (worked out per driveway when a chunk first asks)
##   3. parked cars (VehicleSeeder asks car_spot; it keeps its own cars)
## Every decision is seeded from the thing's own anchor (road and distance
## along it, driveway), never from build order, so a street looks the same
## whichever chunk loads first, and a save rebuilds the same cars.
## try() answers: placed where asked, moved to a nearby legal spot, or refused.
## RULES says what each kind keeps clear of (metres).
class_name Placement
extends RefCounted

const CELL_M := 24.0
const RULES := {
	"hydrant": {"carriageway": 0.3, "building": 0.3, "drive": 1.5, "ramp": 1.5, "crosswalk": 1.5, "hydrant": 25.0},
	"mailbox": {"carriageway": 0.3, "building": 0.2, "drive": 0.5, "ramp": 0.8, "crosswalk": 1.0, "hydrant": 0.9, "well": 0.8, "lamp": 0.5, "pole": 0.5, "mailbox": 0.6, "bin": 0.6},
	"bin": {"carriageway": 0.3, "building": 0.2, "drive": 0.4, "ramp": 0.8, "crosswalk": 1.0, "hydrant": 0.9, "well": 0.8, "lamp": 0.5, "pole": 0.5, "mailbox": 0.6, "bin": 0.7},
	# B2: what stands up along the street ("sight": nothing tall within 6 m of a street corner)
	"pole": {"carriageway": 0.4, "building": 0.3, "drive": 1.0, "ramp": 1.0, "crosswalk": 1.0, "hydrant": 1.0, "lamp": 2.0},
	"tree": {"carriageway": 0.6, "building": 1.0, "drive": 1.0, "ramp": 1.0, "crosswalk": 1.0, "hydrant": 1.0, "lamp": 1.5, "pole": 1.5, "sight": 6.0},
	"palm": {"carriageway": 0.3, "building": 0.5, "drive": 0.8, "ramp": 0.8, "crosswalk": 0.8, "hydrant": 1.0, "lamp": 1.2, "pole": 1.2, "sight": 6.0},
	"sign": {"carriageway": 0.5, "building": 0.3, "drive": 0.8, "ramp": 0.6, "crosswalk": 0.6, "hydrant": 1.0, "lamp": 0.8, "pole": 0.8},
	# B3: cluster pieces (Clusters); tall ones also keep the street corner clear and stay off doorways
	"prop": {"carriageway": 0.3, "building": 0.05, "drive": 0.6, "ramp": 0.8, "crosswalk": 1.0, "hydrant": 1.0, "lamp": 0.5, "pole": 0.5, "well": 0.5, "mailbox": 0.6, "bin": 0.6},
	"tall_prop": {"carriageway": 0.5, "building": 0.1, "drive": 0.8, "ramp": 1.0, "crosswalk": 1.5, "hydrant": 1.5, "lamp": 0.8, "pole": 0.8, "well": 0.6, "door": 2.0, "sight": 6.0, "mailbox": 0.8, "bin": 0.8},
	# California rules of thumb: 15 ft from a hydrant, 20 ft from a crosswalk, clear of driveways and corners
	"car": {"building": 0.5, "drive": 2.9, "ramp": 6.0, "crosswalk": 6.0, "hydrant": 4.6, "corner": 6.0},
}
const SEEN_M := {"hydrant": 25.0}   # a kind whose own rule reaches further is filed that much wider
const HYDRANT_EVERY := Vector2(90.0, 120.0)
const HYDRANT_BACK := 0.5        # behind the kerb line, on the parkway
const KERBED := ["art", "res"]
const CORNER_TIERS := ["art", "res", "ramp", "hill"]
const POLE_EVERY := 42.0
const NUDGES := [1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.5, -4.5]   # along the kerb, to find a legal spot
const CAR_NUDGES := [1.5, -1.5, 3.0, -3.0]
const CAR_GAP := 5.3              # centre to centre: a 4.8 m car and 0.5 m to the next
const MAILBOX_SHARE := 70        # percent of driveways
const NEIGHBOUR_M := 14.0         # driveways this close can crowd each other's items
const BINS_SHARE := 35

static var _cache := {}          # city instance id -> Placement
static var _REACH := _reaches()  # kind -> the widest distance any rule keeps from it
static var _lock := Mutex.new()

var city: CityData
var real: CityReal
var space: RoadSpace
var solid: CityCollision
var stats := {}                  # kind -> {ok, moved, refused}
var _fixed := {}                 # cell -> [[kind, pos, extra]]: drives [c, dir, w, len], crosswalks [c, dir, len], points
var _placed := {}                # cell -> [[kind, pos, heading]]
var _drive_cells := {}           # cell -> [driveway index]
var _poles := {}                 # road index -> its poles [[pos, dir]] (made on first ask)
var _road_ix := {}               # road id -> index in the whole city
var _items := {}                 # driveway index -> its items [[kind, pos, heading, tag]] (made on first ask)

static func _reaches() -> Dictionary:
	var out := {}
	for kind in RULES:
		for what in RULES[kind]:
			out[what] = maxf(float(out.get(what, 0.0)), float(RULES[kind][what]))
	out["car"] = CAR_GAP
	return out

## The placement of `city` (built on first use; a chunk slice leads back to its whole city).
static func of(city_data: CityData) -> Placement:
	city_data = city_data.get_meta("whole", city_data)
	_lock.lock()
	var id := city_data.get_instance_id()
	if not _cache.has(id):
		var p := Placement.new()
		p._build(city_data)
		_cache[id] = p
	var out: Placement = _cache[id]
	_lock.unlock()
	return out

func _build(city_data: CityData) -> void:
	city = city_data
	real = CityReal.load_files()
	space = RoadSpace.of(city)
	solid = CityCollision.new(city)
	for i in city.roads.size():
		_road_ix[city.roads[i].get("id", "")] = i
	for i in city.driveways.size():
		var d: Dictionary = city.driveways[i]
		_file(_fixed, d["c"], 6.0, ["drive", d["c"], [d["dir"], float(d["w"]), float(d["len"])]])
		_drive_cells.get_or_add(_cell(d["c"]), []).append(i)
	for c in city.crosswalks:
		_file(_fixed, c["c"], float(c["len"]) * 0.5 + 2.0, ["crosswalk", c["c"], [c["dir"], float(c["len"])]])
	for r in city.kerb_ramps:
		_file(_fixed, r["c"], 1.0, ["ramp", r["c"], []])
	for w in city.tree_wells:
		_file(_fixed, w, 1.0, ["well", w, []])
	for b in city.buildings:   # B3: tall props stay off doorways
		if b.get("door", Vector2.INF) != Vector2.INF:
			_file(_fixed, b["door"], 1.0, ["door", b["door"], []])
	_hydrants()

## 1. Hydrants: the map's own, then a regular run along every kerbed street.
func _hydrants() -> void:
	for p in real.points:
		if p["kind"] == "hydrant":
			_accept("hydrant", p["p"], 0.0, false)
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		if not r["tier"] in KERBED:
			continue
		var pts: PackedVector2Array = r["pts"]
		var half := KerbRuns.half_of(r) + HYDRANT_BACK
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([String(r.get("id", i)), "hydrant"])   # its own anchor: the road
		var next := rng.randf_range(10.0, HYDRANT_EVERY.y)
		var along := 0.0
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for k in pts.size() - 1:
			var seg := pts[k].distance_to(pts[k + 1])
			if seg < 0.05:
				continue
			var dir := (pts[k + 1] - pts[k]) / seg
			while next <= along + seg:
				var at := pts[k] + dir * (next - along) + dir.orthogonal() * side * half
				try("hydrant", at, dir.angle(), dir)
				side = -side
				next += rng.randf_range(HYDRANT_EVERY.x, HYDRANT_EVERY.y)
			along += seg

## 2. Driveway `di`'s items: a mailbox on one side, the bins on the other (by a hash of
## the driveway). Each keeps clear of the fixed street, the hydrants, and the items of
## the neighbouring driveways listed before it (worked out first, and kept), so the
## answer is the same whichever chunk asks first.
func _items_of(di: int) -> Array:
	if _items.has(di):
		return _items[di]
	var d: Dictionary = city.driveways[di]
	var c: Vector2 = d["c"]
	var others: Array = []
	for dj in _drives_near(c, NEIGHBOUR_M):
		if dj < di:
			others.append_array(_items_of(dj))
	var mine: Array = []
	var into: Vector2 = d["dir"]
	var side := into.orthogonal()
	var half := float(d["w"]) * 0.5
	var roll := absi(hash(c))
	if roll % 100 < MAILBOX_SHARE:
		_place_item(mine, others, "mailbox", c + into * 0.6 + side * (half + 0.7), into.angle(), side, 0)
	if (roll / 100) % 100 < BINS_SHARE:
		for k in 3:   # trash, recycling, yard waste, side by side
			_place_item(mine, others, "bin", c + into * 0.8 - side * (half + 0.8 + k * 0.78), into.angle(), -side, k)
	_items[di] = mine
	return mine

func _drives_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var lo := _cell(p - Vector2.ONE * r)
	var hi := _cell(p + Vector2.ONE * r)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for i in _drive_cells.get(Vector2i(x, y), []):
				if (city.driveways[i]["c"] as Vector2).distance_to(p) <= r:
					out.append(i)
	return out

## One driveway item where asked, or nudged along `slide`, or left out.
func _place_item(mine: Array, others: Array, kind: String, pos: Vector2, heading: float, slide: Vector2, tag: int) -> void:
	var state := "refused"
	for n in [0.0] + NUDGES:
		var p: Vector2 = pos + slide.normalized() * float(n)
		if violations(kind, p).is_empty() and conflicts(kind, p, others + mine).is_empty():
			mine.append([kind, p, heading, tag])
			state = "ok" if n == 0.0 else "moved"
			break
	stats.get_or_add(kind, {"ok": 0, "moved": 0, "refused": 0})[state] += 1

## The things in `list` ([kind, pos, ...]) that `kind` at `pos` stands too close to.
static func conflicts(kind: String, pos: Vector2, list: Array) -> Array:
	var rule: Dictionary = RULES[kind]
	var out: Array = []
	for o in list:
		if rule.has(o[0]) and (o[1] as Vector2).distance_to(pos) < float(rule[o[0]]) and (o[1] as Vector2).distance_to(pos) > 0.001:
			out.append(o[0])
	return out

## Places a `kind` at `pos` or, if it breaks a rule there, the first legal spot nudged
## along `slide`; refuses it if none. {state: ok|moved|refused, pos, broke}.
func try(kind: String, pos: Vector2, heading: float = 0.0, slide: Vector2 = Vector2.ZERO, tag: int = 0) -> Dictionary:
	var broke := violations(kind, pos)
	var state := "ok"
	if not broke.is_empty() and slide != Vector2.ZERO:
		state = "refused"
		for n in NUDGES:
			var p: Vector2 = pos + slide.normalized() * float(n)
			if violations(kind, p).is_empty():
				pos = p
				state = "moved"
				break
	elif not broke.is_empty():
		state = "refused"
	var s: Dictionary = stats.get_or_add(kind, {"ok": 0, "moved": 0, "refused": 0})
	s[state] += 1
	if state != "refused":
		_accept(kind, pos, heading, true, tag)
	return {"state": state, "pos": pos, "broke": broke}

func _accept(kind: String, pos: Vector2, heading: float, counted: bool, tag: int = 0) -> void:
	_file(_placed, pos, SEEN_M.get(kind, 0.0), [kind, pos, heading, tag])
	if not counted:
		stats.get_or_add(kind, {"ok": 0, "moved": 0, "refused": 0})["ok"] += 1

## The rules `kind` breaks at `pos` (none: it may stand there). `own` is a road to ignore
## for "corner" (the one a car parks on).
func violations(kind: String, pos: Vector2, own: int = -1) -> Array:
	var rule: Dictionary = RULES[kind]
	var broke: Array = []
	if rule.has("carriageway") and space.inside(pos, float(rule["carriageway"])):
		broke.append("carriageway")
	if rule.has("corner") and space.inside(pos, float(rule["corner"]), own):
		broke.append("corner")
	if rule.has("building") and solid.blocked(pos, float(rule["building"])):
		broke.append("building")
	if rule.has("sight") and _at_corner(pos, float(rule["sight"])):
		broke.append("sight")
	if rule.has("lamp") and StreetLights.active != null:
		for l in StreetLights.active.near(pos, float(rule["lamp"]) + 1.0):
			if Vector2(l.x, l.y).distance_to(pos) < float(rule["lamp"]):
				broke.append("lamp")
				break
	if rule.has("pole"):
		for q in poles_near(pos, float(rule["pole"])):
			if (q[0] as Vector2).distance_to(pos) > 0.001:
				broke.append("pole")
				break
	for grid in [_fixed, _placed]:
		for it in grid.get(_cell(pos), []):
			var what: String = it[0]
			if not rule.has(what) or broke.has(what):
				continue
			var clear := float(rule[what])
			var far := _distance(what, it, pos)
			if far < clear and not (grid == _placed and (it[1] as Vector2).distance_to(pos) < 0.001):
				broke.append(what)
	return broke

## B2: is `pos` within `m` of two or more streets' carriageways (a corner's sight triangle)?
func _at_corner(pos: Vector2, m: float) -> bool:
	var seen := {}
	for it in space._grid.get(Vector2i((pos / RoadSpace.CELL_M).floor()), []):
		if seen.has(it[3]) or not city.roads[it[3]]["tier"] in CORNER_TIERS:
			continue
		if Geometry2D.get_closest_point_to_segment(pos, it[0], it[1]).distance_to(pos) < float(it[2]) + m:
			seen[it[3]] = true
			if seen.size() >= 2:
				return true
	return false

## B2: wooden power poles down one side of a residential street (road `i`), every
## POLE_EVERY, each nudged along the road to a legal spot or left out. [[pos, dir]],
## made per road on first ask (after the lamps are known).
func poles_of(i: int) -> Array:
	_lock.lock()   # (recursive: safe inside near())
	if _poles.has(i):
		_lock.unlock()
		return _poles[i]
	_poles[i] = []   # no recursion through our own pole check
	var r: Dictionary = city.roads[i]
	var out: Array = []
	if r["tier"] == "res":
		var pts: PackedVector2Array = r["pts"]
		var off: float = float(r.get("w", 6.0)) * 0.5 + 1.1
		var run := POLE_EVERY * 0.5
		for k in pts.size() - 1:
			var seg := pts[k + 1] - pts[k]
			var length := seg.length()
			while run < length and length > 0.0:
				var at := space.clear(pts[k] + seg * (run / length) + seg.normalized().orthogonal() * off, 0.5)
				var got := find("pole", at, seg.normalized())
				if not got.is_empty():
					out.append([got["pos"], seg.normalized()])
				run += POLE_EVERY
			run -= length
	_poles[i] = out
	_lock.unlock()
	return out

## Poles within `r` of `p` (from every residential road near it).
func poles_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var roads := {}
	for it in space._grid.get(Vector2i((p / RoadSpace.CELL_M).floor()), []):
		roads[it[3]] = true
	for i in roads:
		for q in poles_of(i):
			if (q[0] as Vector2).distance_to(p) <= r:
				out.append(q)
	return out

## Where a `kind` may stand at `pos` or nudged along `slide` (nothing is recorded):
## {pos, state: ok|moved} or {} if nowhere near. A slide of zero: here or nowhere.
func find(kind: String, pos: Vector2, slide: Vector2 = Vector2.ZERO) -> Dictionary:
	_lock.lock()
	var out := {}
	for n in ([0.0] + NUDGES if slide != Vector2.ZERO else [0.0]):
		var p: Vector2 = pos + slide.normalized() * float(n)
		if violations(kind, p).is_empty():
			out = {"pos": p, "state": "ok" if n == 0.0 else "moved"}
			break
	stats.get_or_add(kind, {"ok": 0, "moved": 0, "refused": 0})[out.get("state", "refused")] += 1
	_lock.unlock()
	return out

## The whole-city index of road `r` (a chunk slice holds the same road dictionaries).
func road_index(r: Dictionary) -> int:
	return int(_road_ix.get(r.get("id", ""), -1))

## How far `pos` is from a filed thing (a driveway apron, a crosswalk stripe, or a point).
static func _distance(what: String, it: Array, pos: Vector2) -> float:
	var c: Vector2 = it[1]
	if what == "drive":   # the apron: w wide along the kerb, from the gutter to len into the lot
		var into: Vector2 = it[2][0]
		var along := absf((pos - c).dot(into.orthogonal())) - float(it[2][1]) * 0.5
		var depth := (pos - c).dot(into)
		var out := maxf(-1.5 - depth, depth - float(it[2][2]))
		return Vector2(maxf(along, 0.0), maxf(out, 0.0)).length()
	if what == "crosswalk":   # a 3 m wide stripe across the road
		var dir: Vector2 = it[2][0]
		var half := float(it[2][1]) * 0.5
		var q := Geometry2D.get_closest_point_to_segment(pos, c - dir * half, c + dir * half)
		return maxf(0.0, q.distance_to(pos) - 1.5)
	return c.distance_to(pos)

## The parked-car spot nearest `pos` along `dir` that keeps every car rule, or {} if
## there is none. `own`: the road it parks on. `taken`: the caller's own cars so far
## (cars are kept out of the shared table, so two worlds made from one city agree).
func car_spot(pos: Vector2, dir: Vector2, own: int, taken: Dictionary) -> Dictionary:
	_lock.lock()
	var out := {}
	for n in [0.0] + CAR_NUDGES:
		var p: Vector2 = pos + dir * n
		if violations("car", p, own).is_empty() and not _car_near(taken, p, CAR_GAP):
			out = {"pos": p, "state": "ok" if n == 0.0 else "moved"}
			_file(taken, p, 0.0, ["car", p, dir.angle(), 0])
			break
	stats.get_or_add("car", {"ok": 0, "moved": 0, "refused": 0})[out.get("state", "refused")] += 1
	_lock.unlock()
	return out

static func _car_near(taken: Dictionary, p: Vector2, gap: float) -> bool:
	for it in taken.get(_cell(p), []):
		if (it[1] as Vector2).distance_to(p) < gap:
			return true
	return false

## Placed things of `kind` within `r` of `p`: [pos, heading, tag].
func near(kind: String, p: Vector2, r: float) -> Array:
	var out: Array = []
	if kind in ["mailbox", "bin"]:
		_lock.lock()
		for di in _drives_near(p, r + 4.0):
			for it in _items_of(di):
				if it[0] == kind and (it[1] as Vector2).distance_to(p) <= r:
					out.append([it[1], it[2], it[3]])
		_lock.unlock()
		return out
	var lo := _cell(p - Vector2.ONE * r)
	var hi := _cell(p + Vector2.ONE * r)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for it in _placed.get(Vector2i(x, y), []):
				if it[0] == kind and (it[1] as Vector2).distance_to(p) <= r and _home(it[1]) == Vector2i(x, y):
					out.append([it[1], it[2], it[3]])
	return out

static func _cell(p: Vector2) -> Vector2i:
	return Vector2i((p / CELL_M).floor())

## The one cell a thing is listed under for near() (it may be filed in several).
static func _home(p: Vector2) -> Vector2i:
	return _cell(p)

## Files `item` in every cell within `grow` of `p`, so a lookup at any point sees it.
static func _file(grid: Dictionary, p: Vector2, grow: float, item: Array) -> void:
	var reach := grow + float(_REACH.get(item[0], 0.0))   # the widest rule distance anything keeps from this kind
	var lo := _cell(p - Vector2.ONE * reach)
	var hi := _cell(p + Vector2.ONE * reach)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			grid.get_or_add(Vector2i(x, y), []).append(item)
