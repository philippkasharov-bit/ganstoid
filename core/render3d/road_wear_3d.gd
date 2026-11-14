## G2: what years of traffic leave on a road: manhole covers in the lanes,
## drain grates in the gutter, darker patched rectangles and black
## tar-snake crack seals (StreetDetail3D paints the parking ticks). Placed
## by a hash of the road's own points, so the same street looks the same
## every run. Flat quads just above the asphalt.
class_name RoadWear3D
extends RefCounted

const Y := 0.042
const IRON := Color("3d3c3a")
const GRATE := Color("2c2c2b")
const PATCH := Color("666562")
const TAR := Color("3a3a3b")
const HOLE_EVERY := 65.0
const DRAIN_EVERY := 48.0
const PATCH_EVERY := 30.0

## All the wear along road `r` (CityData road dict).
static func add(m: CityMesh3D, r: Dictionary, own: int, space: RoadSpace) -> void:
	var half: float = float(r.get("w", CityMesh3D.ROAD_W.get(r["tier"], 6.0))) * 0.5
	var pts: PackedVector2Array = r["pts"]
	var seed := absi(hash(pts[0]))
	_every(pts, HOLE_EVERY, seed, func(p: Vector2, dir: Vector2, k: int) -> void:
		_disc(m, p + dir.orthogonal() * half * (0.45 if k % 2 == 0 else -0.45), 0.36, IRON))
	_every(pts, DRAIN_EVERY, seed + 1, func(p: Vector2, dir: Vector2, k: int) -> void:
		_rect(m, p + dir.orthogonal() * (half - 0.25) * (1.0 if k % 2 == 0 else -1.0), dir, Vector2(0.45, 0.2), GRATE))
	_every(pts, PATCH_EVERY, seed + 2, func(p: Vector2, dir: Vector2, k: int) -> void:
		if not space.inside(p, 3.0, own):   # B1: not in a junction, where it would run onto the corner
			_scar(m, p, dir, half, seed + k))

## Calls `put(point, direction, index)` every `step` metres along `pts` (first one offset by the seed).
static func _every(pts: PackedVector2Array, step: float, seed: int, put: Callable) -> void:
	var run := float(seed % 1000) / 1000.0 * step
	var k := 0
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var length := seg.length()
		if length < 0.1:
			continue
		while run < length:
			put.call(pts[i] + seg * (run / length), seg / length, k)
			k += 1
			run += step
		run -= length

## A patched rectangle or a crack sealed with tar, by the hash.
static func _scar(m: CityMesh3D, p: Vector2, dir: Vector2, half: float, h: int) -> void:
	var roll := absi(hash(h))
	var across := dir.orthogonal() * (float(roll % 200) / 100.0 - 1.0) * half * 0.7
	if roll % 3 == 0:
		_rect(m, p + across * 0.6, dir, Vector2(0.5 + float(roll % 6) * 0.2, 0.4 + float(roll % 4) * 0.15), SurfaceDetail.mark(PATCH, SurfaceDetail.ASPHALT))   # half-extents: up to 3 x 2 m
		return
	var at := p + across
	var side := dir.orthogonal()
	for s in 4:   # a zig-zag crack, sealed black, kept off the kerb
		var turn := dir.rotated(float((roll >> (s * 3)) % 7 - 3) * 0.3)
		var next := at + turn * (1.0 + float((roll >> s) % 3) * 0.5)
		var off := (next - p).dot(side)
		next -= side * (off - clampf(off, -half * 0.75, half * 0.75))
		_line(m, at, next, 0.08, TAR)
		at = next

## A small flat rectangle centred at `c`, `size` half-extents along / across `along`.
static func _rect(m: CityMesh3D, c: Vector2, along: Vector2, size: Vector2, col: Color) -> void:
	var x := along * size.x
	var y := along.orthogonal() * size.y
	m._quad(m._tool(c), [m._v(c - x - y, Y), m._v(c + x - y, Y), m._v(c + x + y, Y), m._v(c - x + y, Y)], Vector3.UP, col)

static func _line(m: CityMesh3D, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := (b - a).normalized().orthogonal() * w * 0.5
	m._quad(m._tool(a), [m._v(a - n, Y + 0.001), m._v(b - n, Y + 0.001), m._v(b + n, Y + 0.001), m._v(a + n, Y + 0.001)], Vector3.UP, col)

## A round cover: an octagon of radius `r`.
static func _disc(m: CityMesh3D, c: Vector2, r: float, col: Color) -> void:
	var st := m._tool(c)
	for i in 8:
		var a := c + Vector2.from_angle(i * TAU / 8.0) * r
		var b := c + Vector2.from_angle((i + 1) * TAU / 8.0) * r
		m._tri(st, m._v(c, Y + 0.002), m._v(a, Y + 0.002), m._v(b, Y + 0.002), Vector3.UP, col)
