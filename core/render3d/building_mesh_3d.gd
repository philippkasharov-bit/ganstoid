## R3D2: one building's geometry, with variety. Every building rolls its own
## style from its id (the same every run): a wall colour from a palette that
## fits its kind (LA stucco pastels for houses, brick and paint for shops,
## concrete for industry), a base trim, its own window size and spacing, and
## a roof: small houses get a hipped roof of red clay tile or grey shingle,
## bigger flat roofs get a parapet and rooftop boxes (AC units, sheds). Shops
## get a glass front and a coloured awning on the ground floor; garages and
## industry a roll-up door. The door sits flush in the wall it faces.
class_name BuildingMesh3D
extends RefCounted

const STOREY_M := 3.2
const PALETTES := {
	"house": [Color("efe3c8"), Color("f2d2b6"), Color("dfe8d2"), Color("f0c9b3"), Color("d6e1e6"), Color("f6f1e7"), Color("e8d3a9"), Color("cfdcc4")],
	"apartments": [Color("e3d2b0"), Color("d9c3a0"), Color("efe6d6"), Color("cdbfa7"), Color("e6cfc0"), Color("d8d6cc")],
	"commercial": [Color("b5654a"), Color("c9b9a4"), Color("e7dccb"), Color("8f9a9c"), Color("d4b483"), Color("a85a3c")],
	"industrial": [Color("b4b8bc"), Color("a9aaa4"), Color("c2bfb6"), Color("9ea6ab")],
	"garage": [Color("d8d2c4"), Color("c7c3b8")],
	"civic": [Color("c7a98f"), Color("e6e0d2"), Color("b9b2a3")],
	"building": [Color("cfc3ad"), Color("d9cdb5"), Color("c4bba9")],
}
const ROOF_TILE := [Color("b4553a"), Color("a64b33"), Color("c0653f")]   # Spanish clay
const ROOF_SHINGLE := [Color("5d5a57"), Color("6b6560"), Color("4f4d4c")]
const ROOF_FLAT := [Color("8a8478"), Color("9a958a"), Color("7d786f"), Color("d9d6cf"), Color("b9a98c"), Color("5f5c58")]   # gravel, white cool roof, tar
const AWNINGS := [Color("b23a3a"), Color("2f6d8f"), Color("3f7f4f"), Color("c08a2e"), Color("6b4a8f")]
const GLASS := Color("3b4a5c")
const SHOP_GLASS := Color("5a7385")
const DOOR := Color("3a2a1e")
const FRAME := Color("ece6d8")
const ROLLUP := Color("8d9093")
const TRIM := 0.45
const GLOW := {"commercial": 0.85, "apartments": 0.45, "house": 0.35, "civic": 0.5, "industrial": 0.15, "garage": 0.0}   # R3D10: share of windows lit at night
const DOOR_W := 1.1
const DOOR_H := 2.1
const HIP_MAX_AREA := 400.0
const HULL_FILL := 0.82   # a footprint this close to its hull takes a hipped roof
const EAVES := 1.06

## Adds building `b` to SurfaceTool `st`. `v` maps a map point + height to 3D;
## `tag` (city index + 1) lets the Cutaway cut it whole.
static func add(st: SurfaceTool, b: Dictionary, v: Callable, tag: int = 0) -> void:
	var poly := _open(b["poly"])
	if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = String(b["id"]).hash()
	var kind: String = b["kind"]
	var levels: int = maxi(1, int(b.get("levels", 1)))
	var storey := STOREY_M * rng.randf_range(0.92, 1.1)
	var h := levels * storey
	var pal: Array = PALETTES.get(kind, PALETTES["building"])
	var col: Color = pal[rng.randi() % pal.size()].lightened(rng.randf_range(-0.04, 0.05))
	var style := {"win_w": rng.randf_range(0.8, 1.6), "win_h": rng.randf_range(1.0, 1.5), "gap": rng.randf_range(2.4, 4.2),
		"shop": (kind == "commercial") and rng.randf() < 0.8, "rollup": kind in ["industrial", "garage"] and rng.randf() < 0.6,
		"awning": AWNINGS[rng.randi() % AWNINGS.size()], "storey": storey,
		"tag": tag, "glow": GLOW.get(kind, 0.3), "seed": rng.randi()}
	st.set_uv(Vector2(0, tag))   # R3D7: the Cutaway cuts this building whole by its tag
	var ccw := _ccw(poly)
	var span := InteriorSolid.door_span(poly, b.get("door", Vector2.INF))   # R3D14: the same door the sim lets you through
	var door_edge := int(span.x)
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		if a.distance_to(c) < 0.05:
			continue
		var e := c - a
		var out := (Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)).normalized()
		var n := Vector3(out.x, 0, out.y)
		quad(st, [v.call(a, 0.0), v.call(c, 0.0), v.call(c, h), v.call(a, h)], n, col)
		quad(st, [v.call(a + out * 0.02, 0.0), v.call(c + out * 0.02, 0.0), v.call(c + out * 0.02, TRIM), v.call(a + out * 0.02, TRIM)], n, col.darkened(0.3))
		var door_t := span.y if i == door_edge else -1.0
		_openings(st, v, a, c, out, levels, door_t, style)
	_roof(st, v, poly, h, kind, levels, rng)
	st.set_uv(Vector2.ZERO)   # what follows (roads, the next lot) is not this building

static func quad(st: SurfaceTool, q: Array, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	for k in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(q[k])

static func flat(st: SurfaceTool, v: Callable, poly: PackedVector2Array, h: float, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	st.set_color(col)
	st.set_normal(Vector3.UP)
	for k in tris:
		st.add_vertex(v.call(poly[k], h))

## A hipped roof on a small convex house; otherwise flat with a parapet and rooftop boxes.
static func _roof(st: SurfaceTool, v: Callable, poly: PackedVector2Array, h: float, kind: String, levels: int, rng: RandomNumberGenerator) -> void:
	var area := absf(_area(poly))
	var hull := _open(Geometry2D.convex_hull(poly))
	if kind in ["house", "apartments"] and levels <= 2 and area < HIP_MAX_AREA and area > HULL_FILL * absf(_area(hull)):
		var tiles: Array = ROOF_TILE if rng.randf() < 0.65 else ROOF_SHINGLE
		var col: Color = tiles[rng.randi() % tiles.size()]
		var apex := _centroid(hull)
		var top := h + clampf(sqrt(area) * 0.28, 1.2, 3.2)
		for i in hull.size():   # on the hull, eaves a little proud: notches hide under the overhang
			var a := apex + (hull[i] - apex) * EAVES
			var c := apex + (hull[(i + 1) % hull.size()] - apex) * EAVES
			var tri: Array = [v.call(a, h), v.call(c, h), v.call(apex, top)]
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			st.set_color(col)
			st.set_normal(n if n.y > 0.0 else -n)   # real slope normal: each face catches the sun differently
			for p in tri:
				st.add_vertex(p)
		return
	var flat_col: Color = ROOF_FLAT[rng.randi() % ROOF_FLAT.size()]
	flat(st, v, poly, h, flat_col)
	for i in poly.size():   # parapet: a low lip round the edge
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		quad(st, [v.call(a, h), v.call(c, h), v.call(c, h + 0.5), v.call(a, h + 0.5)], Vector3.UP, flat_col.darkened(0.15))
	var units := mini(int(area / 120.0), 4)
	var mid := _centroid(poly)
	for k in units:   # AC units and roof sheds
		var at := mid + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * sqrt(area) * 0.25
		if Geometry2D.is_point_in_polygon(at, poly):
			_box(st, v, at, Vector2(rng.randf_range(1.0, 2.6), rng.randf_range(1.0, 2.0)), h, rng.randf_range(0.8, 1.6), Color("b9bcbf").darkened(rng.randf() * 0.2))

static func _box(st: SurfaceTool, v: Callable, at: Vector2, size: Vector2, h: float, tall: float, col: Color) -> void:
	var s := size * 0.5
	var c := [at + Vector2(-s.x, -s.y), at + Vector2(s.x, -s.y), at + Vector2(s.x, s.y), at + Vector2(-s.x, s.y)]
	for i in 4:
		quad(st, [v.call(c[i], h), v.call(c[(i + 1) % 4], h), v.call(c[(i + 1) % 4], h + tall), v.call(c[i], h + tall)], Vector3.UP, col.darkened(0.15))
	quad(st, [v.call(c[0], h + tall), v.call(c[1], h + tall), v.call(c[2], h + tall), v.call(c[3], h + tall)], Vector3.UP, col)

## Windows by the building's own size and spacing; the door flush in its
## wall; on a shop's front a glass band and an awning, on a garage a roll-up.
static func _openings(st: SurfaceTool, v: Callable, a: Vector2, c: Vector2, out: Vector2, levels: int, door_t: float, s: Dictionary) -> void:
	var length := a.distance_to(c)
	var dir := (c - a) / length
	var n := Vector3(out.x, 0, out.y)
	var proud := out * 0.04
	var front := door_t >= 0.0
	if front and s["shop"] and length > 4.0:
		st.set_uv(Vector2(1.0, s["tag"]))   # R3D10: a shop front glows at night
		quad(st, [v.call(a + dir * 0.5 + proud, 0.4), v.call(c - dir * 0.5 + proud, 0.4), v.call(c - dir * 0.5 + proud, 2.6), v.call(a + dir * 0.5 + proud, 2.6)], n, SHOP_GLASS)
		st.set_uv(Vector2(0.0, s["tag"]))
		quad(st, [v.call(a + proud, 2.8), v.call(c + proud, 2.8), v.call(c + out * 1.3, 2.4), v.call(a + out * 1.3, 2.4)], Vector3.UP, s["awning"])
	elif front:
		var mid := a.lerp(c, door_t) + proud
		var w: float = 3.0 if s["rollup"] else DOOR_W
		var half := dir * w * 0.5
		var tall: float = 3.0 if s["rollup"] else DOOR_H
		quad(st, [v.call(mid - half * 1.15, 0.0), v.call(mid + half * 1.15, 0.0), v.call(mid + half * 1.15, tall + 0.15), v.call(mid - half * 1.15, tall + 0.15)], n, FRAME)
		var inner := mid + proud * 0.5
		quad(st, [v.call(inner - half, 0.0), v.call(inner + half, 0.0), v.call(inner + half, tall), v.call(inner - half, tall)], n, ROLLUP if s["rollup"] else DOOR)
	var count := int(length / float(s["gap"]))
	for lv in levels:
		if lv == 0 and front and s["shop"]:
			continue
		for k in count:
			var t := (k + 0.5) / count
			if lv == 0 and front and absf(t - door_t) * length < 2.2:
				continue
			var p := a.lerp(c, t) + proud
			var w2 := dir * float(s["win_w"]) * 0.5
			var y := lv * float(s["storey"]) + 1.0
			var lit := float(absi(hash([s["seed"], a, k, lv])) % 100) < float(s["glow"]) * 100.0   # R3D10: someone home
			st.set_uv(Vector2(0.8 if lit else 0.0, s["tag"]))
			quad(st, [v.call(p - w2, y), v.call(p + w2, y), v.call(p + w2, y + s["win_h"]), v.call(p - w2, y + s["win_h"])], n, GLASS)
			st.set_uv(Vector2(0.0, s["tag"]))

static func _open(poly: PackedVector2Array) -> PackedVector2Array:
	return poly.slice(0, poly.size() - 1) if poly.size() > 3 and poly[0] == poly[poly.size() - 1] else poly

static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].x * poly[(i + 1) % poly.size()].y - poly[(i + 1) % poly.size()].x * poly[i].y
	return s * 0.5

static func _ccw(poly: PackedVector2Array) -> bool:
	return _area(poly) > 0.0

static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / poly.size()
