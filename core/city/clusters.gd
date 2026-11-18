## VS2B3: designed groups of street things instead of random scatter. Each
## template is a list of [kind, offset (along the front, out from it), turn,
## required?]; Clusters finds anchors in the city data (apartment doors, shop
## doors, bus stops, alleys, driveways, lots, courts), picks the ones that win a
## hash, keeps at most CAP per 96 m block (the best hashes, so the pick never
## depends on build order), and stands every piece through Placement (a
## required piece that has no legal spot drops the whole group). Made on
## first ask, the same in every chunk; ClusterProps3D draws them.
class_name Clusters
extends RefCounted

const BLOCK_M := 96.0
const CAP := 4                    # groups per block at most
## template -> [share of its anchors (percent), [kind, along, out, turn (rad), required]...]
const TEMPLATES := {
	"stoop": [45, [["chair", -1.3, 1.2, 0.3, true], ["chair", 1.3, 1.1, -0.4, false], ["crate", -1.9, 0.7, 0.0, false], ["trash_bag", 1.9, 0.6, 0.0, false]]],
	"corner_store": [70, [["payphone", -2.4, 0.6, 0.0, true], ["news_box", 2.2, 0.7, 0.0, false], ["news_box", 2.8, 0.7, 0.0, false], ["ad_board", 1.2, 1.6, 0.4, false]]],
	"laundromat": [8, [["bench", -2.0, 0.7, 0.0, true], ["laundry_cart", 1.6, 0.8, 0.2, false], ["laundry_cart", 2.4, 0.9, -0.3, false]]],
	"taco_stand": [6, [["cart", 0.0, 2.6, 0.0, true], ["umbrella", 0.0, 2.6, 0.0, false], ["cooler", 1.4, 2.2, 0.0, false], ["chair", -1.6, 2.4, 0.5, false]]],
	"car_wash": [3, [["tall_sign", 0.0, 0.0, 0.0, true], ["bucket", 1.5, -1.0, 0.0, false], ["bucket", -1.6, -0.8, 0.0, false]]],
	"bus_stop": [100, [["shelter", 0.0, 1.4, 0.0, true], ["bench", 0.0, 1.5, 0.0, false], ["trash_bag", 2.1, 1.0, 0.0, false]]],
	"yard_car": [6, [["car_shell", 0.0, 4.5, 0.0, true], ["tire", 2.0, 3.2, 0.0, false], ["tire", 2.3, 2.6, 0.0, false]]],
	"alley_dumpster": [55, [["dumpster", 0.0, 1.2, 0.0, true], ["pallet", 1.8, 1.0, 0.3, false], ["trash_bag", -1.5, 0.9, 0.0, false]]],
	"shop_dumpster": [25, [["dumpster", 0.0, 1.4, 0.0, true], ["pallet", 1.9, 1.1, -0.2, false]]],
	"vacant_lot": [100, [["mattress", 0.0, 0.0, 0.4, true], ["tire", 2.1, 0.6, 0.0, false], ["trash_bag", -1.8, 1.2, 0.0, false], ["trash_bag", -2.4, 0.4, 0.0, false], ["crate", 1.0, -1.6, 0.2, false]]],
	"construction": [100, [["fence_panel", -2.5, 0.0, 0.0, true], ["fence_panel", 0.0, 0.0, 0.0, true], ["fence_panel", 2.5, 0.0, 0.0, true], ["work_sign", 0.0, -1.2, 0.0, false], ["toilet", 4.4, -1.0, 0.0, false]]],
	"court_corner": [100, [["hoop", 0.0, 0.0, 0.0, true], ["bench", 3.0, -0.8, 0.0, false], ["boombox", 3.6, -0.2, 0.0, false]]],
}
## kinds that stand tall (kept out of a street corner's sight triangle, clear of doors)
const TALL := ["shelter", "cart", "umbrella", "tall_sign", "car_shell", "dumpster", "fence_panel", "toilet", "hoop"]

static var _cache := {}   # Placement instance id -> Clusters
static var _lock := Mutex.new()

var place: Placement
var _all: Array = []      # [template, anchor, along (unit), out (unit), seed] that won their block
var _made := {}           # index into _all -> its pieces [[kind, pos, turn]]
var _cells := {}          # 24 m cell -> [index into _all]

static func of(p: Placement) -> Clusters:
	_lock.lock()
	var id := p.get_instance_id()
	if not _cache.has(id):
		var c := Clusters.new()
		c.place = p
		c._anchors()
		_cache[id] = c
	var out: Clusters = _cache[id]
	_lock.unlock()
	return out

## Every anchor the city offers, the winners of each block kept.
func _anchors() -> void:
	var city := place.city
	var real := place.real
	var found: Array = []
	var junctions := CityDetail3D._junctions()
	for b in city.buildings:
		var door: Vector2 = b.get("door", Vector2.INF)
		if door == Vector2.INF:
			continue
		var poly := CityMesh3D._open(b["poly"])
		var face := _face(poly, door)
		if face.is_empty():
			continue
		match b["kind"]:
			"apartments":
				found.append(["stoop", door, face[0], face[1]])
			"commercial":
				var corner := not junctions.near(door, 25.0).is_empty()
				found.append(["corner_store" if corner else "laundromat", door, face[0], face[1]])
				if not corner:
					found.append(["taco_stand", door, face[0], face[1]])
				var back := _centroid(poly) * 2.0 - door   # the far side of the building, out the back
				found.append(["shop_dumpster", _outside(poly, back, door), face[0], -face[1]])
	for p in real.points:
		if p["kind"] == "bus_stop":
			var near := _road_near(p["p"])
			if not near.is_empty():
				found.append(["bus_stop", p["p"], near[0], near[1]])
	for i in city.driveways.size():
		var d: Dictionary = city.driveways[i]
		found.append(["yard_car", d["c"], (d["dir"] as Vector2).orthogonal(), d["dir"]])
	for r in city.roads:
		if r["tier"] != "alley":
			continue
		var pts: PackedVector2Array = r["pts"]
		var run := 20.0
		for k in pts.size() - 1:
			var seg := pts[k + 1] - pts[k]
			var length := seg.length()
			while run < length and length > 0.0:
				var dir := seg / length
				var side := 1.0 if absi(hash(pts[k] + dir * run)) % 2 == 0 else -1.0
				var at := pts[k] + dir * run + dir.orthogonal() * side * (CityMesh3D.ROAD_W["alley"] * 0.5)
				found.append(["alley_dumpster", at, dir, dir.orthogonal() * side])
				run += 45.0
			run -= length
	for lot in real.lots:
		if lot["use"] == "open":
			found.append(["vacant_lot", _centroid(lot["poly"]), Vector2.RIGHT, Vector2.DOWN])
		elif lot["use"] in ["commercial", "industrial"] and _area(lot["poly"]) > 900.0:
			found.append(["car_wash", _centroid(lot["poly"]), Vector2.RIGHT, Vector2.DOWN])
	for s in real.surfaces:
		match s["kind"]:
			"vacant":
				found.append(["vacant_lot", _centroid(s["poly"]), Vector2.RIGHT, Vector2.DOWN])
			"construction":
				var poly: PackedVector2Array = CityMesh3D._open(s["poly"])
				var e := (poly[1] - poly[0]).normalized()
				found.append(["construction", poly[0].lerp(poly[1], 0.5) + e.orthogonal() * 0.0, e, e.orthogonal()])
			"pitch":
				var poly: PackedVector2Array = CityMesh3D._open(s["poly"])
				var inward := (_centroid(poly) - poly[0]).normalized()
				found.append(["court_corner", poly[0] + inward * 1.5, inward.orthogonal(), inward])
	# the share that each template takes, then the best few per block
	var by_block := {}
	for f in found:
		var seed := absi(hash([f[0], f[1]]))
		if seed % 100 >= int(TEMPLATES[f[0]][0]):
			continue
		by_block.get_or_add(Vector2i((f[1] / BLOCK_M).floor()), []).append(f + [seed])
	for block in by_block:
		var list: Array = by_block[block]
		list.sort_custom(func(a: Array, b: Array) -> bool: return a[4] < b[4])
		for f in list.slice(0, CAP):
			_cells.get_or_add(Placement._cell(f[1]), []).append(_all.size())
			_all.append(f)

## The wall of `poly` nearest `door`: [its direction, out of the building], or [].
static func _face(poly: PackedVector2Array, door: Vector2) -> Array:
	var best := INF
	var out: Array = []
	var ccw := CityMesh3D._ccw(poly)
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		if a.distance_to(c) < 0.5:
			continue
		var d := Geometry2D.get_closest_point_to_segment(door, a, c).distance_to(door)
		if d < best:
			best = d
			var e := (c - a).normalized()
			out = [e, (Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x))]
	return out

## A point just outside `poly` behind `back`, or the door if none.
static func _outside(poly: PackedVector2Array, back: Vector2, door: Vector2) -> Vector2:
	var dir := (back - door).normalized()
	var p := back
	for n in 20:
		if not Geometry2D.is_point_in_polygon(p, poly):
			return p + dir * 1.0
		p += dir * 1.0
	return door

func _road_near(p: Vector2) -> Array:
	var best := INF
	var out: Array = []
	for it in place.space._grid.get(Vector2i((p / RoadSpace.CELL_M).floor()), []):
		var q := Geometry2D.get_closest_point_to_segment(p, it[0], it[1])
		if q.distance_to(p) < best and q.distance_to(p) > 0.01:
			best = q.distance_to(p)
			out = [(it[1] - it[0]).normalized(), (p - q).normalized()]
	return out

static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p / poly.size()
	return c

static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5

## Cluster `i`'s pieces, stood through Placement (made once).
func pieces(i: int) -> Array:
	_lock.lock()
	if not _made.has(i):
		var f: Array = _all[i]
		var tpl: Array = TEMPLATES[f[0]][1]
		var along: Vector2 = f[2]
		var out: Vector2 = f[3]
		var got: Array = []
		var items := _items_near(f[1])
		for t in tpl:
			var want: Vector2 = f[1] + along * float(t[1]) + out * float(t[2])
			var kind: String = "tall_prop" if t[0] in TALL else "prop"
			var spot := place.find(kind, want, along)
			if not spot.is_empty() and not Placement.conflicts(kind, spot["pos"], items).is_empty():
				spot = {}
			if spot.is_empty():
				if t[4]:
					got = []   # a required piece has nowhere to stand: no group here
					break
				continue
			got.append([t[0], spot["pos"], out.angle() + float(t[3])])
		_made[i] = got
	var out_list: Array = _made[i]
	_lock.unlock()
	return out_list

## Mailboxes and bins near `p` (clusters keep clear of them).
func _items_near(p: Vector2) -> Array:
	var out: Array = []
	for kind in ["mailbox", "bin"]:
		for it in place.near(kind, p, 12.0):
			out.append([kind, it[0]])
	return out

## Every cluster piece within `r` of `p`: [template, kind, pos, turn].
func near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var lo := Placement._cell(p - Vector2.ONE * (r + 12.0))
	var hi := Placement._cell(p + Vector2.ONE * (r + 12.0))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for i in _cells.get(Vector2i(x, y), []):
				for piece in pieces(i):
					if (piece[1] as Vector2).distance_to(p) <= r:
						out.append([_all[i][0], piece[0], piece[1], piece[2]])
	return out

## How many groups won their block, by template.
func counts() -> Dictionary:
	var out := {}
	for f in _all:
		out[f[0]] = int(out.get(f[0], 0)) + 1
	return out
