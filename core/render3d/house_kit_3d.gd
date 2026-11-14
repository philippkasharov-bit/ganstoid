## K4: a house built from the Blender kit on its real footprint. Each wall
## is generated with rectangular holes, and the kit's parts sit in them: the
## front door where the sim's door is, a garage door on the wall nearest a
## driveway, sash windows about every 3 m on every storey (lined up), a wide
## picture window beside the front door, now and then a small bathroom
## window; corner boards, a porch on some houses, a utility meter. Each
## house paints its trim and door its own colours. Spec:
## claude/ganstoid-house-kit-spec.md.
class_name HouseKit3D
extends RefCounted

const SILL := 0.9
const WIN_H := 1.3
const SPACING := 3.5
const SIDE_KEEP := 75     # percent of side-wall window spots that get a window (fronts get them all)
const CORNER_GAP := 0.4
const MIN_EDGE := 2.6
const STEP := 0.17
const WIDTH := {"kit_window_sash": 1.0, "kit_window_wide": 1.8, "kit_window_small": 0.6, "kit_door_front": 1.0, "kit_door_garage": 2.6}
const TRIMS := [Color("f1ece2"), Color("e8dcc4"), Color("5a4636"), Color("b9c2a8"), Color("ffffff")]
const GARAGE_REACH := 6.0
const PORCH_SHARE := 4   # in ten

## What one house keeps for all its walls.
static func context(m: CityMesh3D, poly: PackedVector2Array, col: Color, style: Dictionary, door_edge: int) -> Dictionary:
	var seed := int(style["seed"])
	return {"tag": style["tag"], "col": col, "seed": seed, "glow": style["glow"], "storey": style["storey"],
		"trim": TRIMS[absi(seed) % TRIMS.size()], "door": absi(seed) % KitBatch3D.DOOR_PAINT.size(),
		"garage": _garage(m.aprons, poly, door_edge), "porch": absi(seed / 7) % 10 < PORCH_SHARE, "door_edge": door_edge}

## One wall a..c (edge `i`), facing `out`, `h` tall: holed, trimmed, its parts placed.
static func wall(m: CityMesh3D, st: SurfaceTool, v: Callable, a: Vector2, c: Vector2, out: Vector2, i: int, levels: int, h: float, door_t: float, ctx: Dictionary) -> void:
	var length := a.distance_to(c)
	var dir := (c - a) / length
	var holes: Array = []
	if door_t >= 0.0:
		holes.append(_hole("kit_door_front", door_t * length, STEP, STEP + 2.1))
	if int(ctx["garage"].x) == i:
		holes.append(_hole("kit_door_garage", ctx["garage"].y * length, 0.0, 2.1))
	_windows(holes, length, levels, i, door_t >= 0.0, ctx)
	var n := Vector3(out.x, 0, out.y)
	_holed(st, v, a, dir, length, h, holes, n, ctx["col"])
	_holed(st, v, a + out * 0.02, dir, length, BuildingMesh3D.TRIM, holes, n, ctx["col"].darkened(0.3))
	for hole in holes:
		_put(m, v, a + dir * float(hole["x"]), dir, out, hole["part"], float(hole["y0"]), hole.get("lit", 0.0), ctx)
	if door_t >= 0.0 and ctx["porch"] and length >= 3.0:
		_put(m, v, a + dir * door_t * length, dir, out, "kit_porch", 0.0, 0.0, ctx)
	if i == (int(ctx["door_edge"]) + 1) and length >= 2.4:
		_put(m, v, a + dir * 0.6, dir, out, "kit_meter", 0.0, 0.0, ctx)

## A corner board up every corner of the footprint.
static func corners(m: CityMesh3D, v: Callable, poly: PackedVector2Array, h: float, ctx: Dictionary) -> void:
	for k in poly.size():
		var e := poly[(k + 1) % poly.size()] - poly[k]
		var xform := Transform3D(Basis(Vector3.UP, -e.angle()).scaled_local(Vector3(1, h, 1)), v.call(poly[k], 0.0))
		m.kit_put(poly[k], "kit_trim_corner", xform, ctx["trim"], KitBatch3D.custom(ctx["tag"], 0.0, ctx["door"]))

static func _hole(part: String, x: float, y0: float, y1: float) -> Dictionary:
	var half: float = WIDTH[part] * 0.5
	return {"part": part, "x": x, "x0": x - half, "x1": x + half, "y0": y0, "y1": y1}

## Windows about every SPACING metres on each storey, clear of corners, the door and the garage.
static func _windows(holes: Array, length: float, levels: int, edge: int, front: bool, ctx: Dictionary) -> void:
	if length < MIN_EDGE:
		return
	var count := maxi(1, int((length - 0.8) / SPACING))
	for k in count:
		var x := (k + 0.5) * length / count
		for lv in levels:
			var part := _pick(length, lv, front, edge, k, ctx)
			var sill := 1.5 if part == "kit_window_small" else SILL
			var y0: float = lv * float(ctx["storey"]) + sill
			var hole := _hole(part, x, y0, y0 + (0.6 if part == "kit_window_small" else WIN_H))
			if hole["x0"] < CORNER_GAP or hole["x1"] > length - CORNER_GAP or _clashes(hole, holes):
				continue
			if not front and absi(hash([ctx["seed"], edge, k, 3])) % 100 >= SIDE_KEEP:
				continue
			hole["lit"] = 0.8 if absi(hash([ctx["seed"], edge, k, lv])) % 100 < int(float(ctx["glow"]) * 100.0) else 0.0
			holes.append(hole)

static func _pick(length: float, lv: int, front: bool, edge: int, k: int, ctx: Dictionary) -> String:
	if lv == 0 and front and length >= 6.0 and k == 0:
		return "kit_window_wide"
	if lv == 0 and not front and absi(hash([ctx["seed"], edge, k])) % 4 == 0:
		return "kit_window_small"
	return "kit_window_sash"

static func _clashes(hole: Dictionary, holes: Array) -> bool:
	for o in holes:
		if hole["x0"] < o["x1"] + 0.3 and hole["x1"] > o["x0"] - 0.3 and hole["y0"] < o["y1"] + 0.2 and hole["y1"] > o["y0"] - 0.2:
			return true
	return false

## A wall from a along dir, `length` long and `h` tall, with the holes left open (column by column).
static func _holed(st: SurfaceTool, v: Callable, a: Vector2, dir: Vector2, length: float, h: float, holes: Array, n: Vector3, col: Color) -> void:
	var xs := [0.0, length]
	for o in holes:
		xs.append_array([clampf(o["x0"], 0.0, length), clampf(o["x1"], 0.0, length)])
	xs.sort()
	for k in xs.size() - 1:
		var xa: float = xs[k]
		var xb: float = xs[k + 1]
		if xb - xa < 0.005:
			continue
		var y := 0.0
		for gap in _gaps(holes, xa, xb):
			if gap.x > y:
				BuildingMesh3D.quad(st, [v.call(a + dir * xa, y), v.call(a + dir * xb, y), v.call(a + dir * xb, minf(gap.x, h)), v.call(a + dir * xa, minf(gap.x, h))], n, col)
			y = maxf(y, gap.y)
		if y < h:
			BuildingMesh3D.quad(st, [v.call(a + dir * xa, y), v.call(a + dir * xb, y), v.call(a + dir * xb, h), v.call(a + dir * xa, h)], n, col)

## The holes spanning the column xa..xb, as sorted (y0, y1).
static func _gaps(holes: Array, xa: float, xb: float) -> Array:
	var gaps: Array = []
	for o in holes:
		if o["x0"] <= xa + 0.001 and o["x1"] >= xb - 0.001:
			gaps.append(Vector2(o["y0"], o["y1"]))
	gaps.sort()
	return gaps

## The garage: the edge (not the door's) nearest a driveway apron within reach, long enough for the door.
static func _garage(aprons: PackedVector2Array, poly: PackedVector2Array, door_edge: int) -> Vector2:
	var best := Vector2(-1, -1)
	var best_d := GARAGE_REACH
	for p in aprons:
		if p.distance_to(poly[0]) > 40.0:
			continue
		for k in poly.size():
			var a := poly[k]
			var c := poly[(k + 1) % poly.size()]
			var length := a.distance_to(c)
			var near := Geometry2D.get_closest_point_to_segment(p, a, c)
			var t := a.distance_to(near) / maxf(length, 0.01)
			if k != door_edge and length >= 3.6 and near.distance_to(p) < best_d and t * length > 1.6 and (1.0 - t) * length > 1.6:
				best_d = near.distance_to(p)
				best = Vector2(k, t)
	return best

## One part on the wall at map point `at` (bottom-centre of its opening at height y).
static func _put(m: CityMesh3D, v: Callable, at: Vector2, dir: Vector2, out: Vector2, part: String, y: float, lit: float, ctx: Dictionary) -> void:
	var basis := Basis(Vector3(-dir.x, 0, -dir.y), Vector3.UP, Vector3(out.x, 0, out.y))   # right-handed: the part's +z faces out
	m.kit_put(at, part, Transform3D(basis, v.call(at, y)), ctx["trim"], KitBatch3D.custom(ctx["tag"], lit, ctx["door"]))
