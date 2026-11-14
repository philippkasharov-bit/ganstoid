## G1: the small geometry that makes a box read as a building: every window
## gets a frame, a sill that sticks out and (wide ones) a mullion; front
## doors a concrete step; hipped roofs a fascia board under the eaves and
## sometimes a chimney; flat roofs a thick parapet with a coping cap;
## apartments the odd window AC unit; shops a sign band over the awning.
## All into the building's SurfaceTool, with the building's tag (UV.y) so
## the Cutaway still cuts it whole. BuildingMesh3D decides where; this draws.
class_name BuildingDetail3D
extends RefCounted

const FRAME := Color("ece6d8")
const SILL := Color("d9d3c4")
const STEP := Color("c9c4b8")
const FASCIA := Color("e8e2d4")
const CHIMNEY := Color("a9705a")
const AC := Color("c9ccce")
const SIGNS := [Color("1f2a44"), Color("f2efe6"), Color("7a1f1f"), Color("2f4f3a")]
const GLASS_OUT := 0.05
const FRAME_M := 0.07

## A window centred at `p` (map), bottom at `y`, `half` (map vector) half its width.
static func window(st: SurfaceTool, v: Callable, p: Vector2, half: Vector2, out: Vector2, y: float, h: float, glass: Color, glow: float, tag: int) -> void:
	var n := Vector3(out.x, 0, out.y)
	var dir := half.normalized()
	var f := dir * FRAME_M
	_plane(st, v, p + out * 0.03, half + f, y - FRAME_M, y + h + FRAME_M, n, SurfaceDetail.mark(FRAME, SurfaceDetail.NONE))
	st.set_uv(Vector2(glow, tag))   # R3D10: only the glass glows
	_plane(st, v, p + out * GLASS_OUT, half, y, y + h, n, glass)
	st.set_uv(Vector2(0.0, tag))
	if half.length() > 0.6:   # a wide window is two panes
		_plane(st, v, p + out * (GLASS_OUT + 0.005), dir * 0.035, y, y + h, n, FRAME)
	var sill_half := half + f * 1.6
	_ledge(st, v, p + out * 0.03, sill_half, out, y - FRAME_M - 0.07, 0.07, 0.13, SILL)

## A concrete step in front of a door `half` wide (map vector).
static func stoop(st: SurfaceTool, v: Callable, mid: Vector2, half: Vector2, out: Vector2) -> void:
	_ledge(st, v, mid, half + half.normalized() * 0.3, out, 0.0, 0.17, 0.9, STEP)

## A fascia board hanging under the eave edge a..c (map), at height `h`.
static func fascia(st: SurfaceTool, v: Callable, a: Vector2, c: Vector2, h: float) -> void:
	var e := c - a
	BuildingMesh3D.quad(st, [v.call(a, h), v.call(c, h), v.call(c, h - 0.22), v.call(a, h - 0.22)], Vector3(e.y, 0, -e.x).normalized(), FASCIA)

## A brick chimney at `at` from `base` up past the ridge to `top`.
static func chimney(st: SurfaceTool, v: Callable, at: Vector2, base: float, top: float) -> void:
	box(st, v, at, Vector2(0.75, 0.6), base, top - base, SurfaceDetail.mark(CHIMNEY, SurfaceDetail.BRICK))
	box(st, v, at, Vector2(0.9, 0.75), top, 0.12, Color("8a8580"))   # its cap

## G4: a satellite dish on a short mast at `at`, standing on `y`, looking south and up.
static func dish(st: SurfaceTool, v: Callable, at: Vector2, y: float) -> void:
	box(st, v, at, Vector2(0.06, 0.06), y, 0.5, Color("8f918e"))
	var look := Vector3(0.25, 0.75, 0.6).normalized()   # map +y is south: LA dishes face the southern sky
	var right := look.cross(Vector3.UP).normalized()
	var up := right.cross(look).normalized()
	var c: Vector3 = v.call(at, y + 0.6) + look * 0.08
	st.set_color(Color("e4e3de"))
	st.set_normal(look)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		for p in [c - look * 0.1, c + (right * cos(a0) + up * sin(a0)) * 0.34, c + (right * cos(a1) + up * sin(a1)) * 0.34]:
			st.add_vertex(p)

## A window AC unit under a window, sticking out of the wall.
static func ac_unit(st: SurfaceTool, v: Callable, p: Vector2, dir: Vector2, out: Vector2, y: float) -> void:
	_ledge(st, v, p + out * 0.03, dir * 0.33, out, y - 0.42, 0.38, 0.45, AC)

## A shop's sign band over its awning, along the wall a..c.
static func sign_band(st: SurfaceTool, v: Callable, a: Vector2, c: Vector2, out: Vector2, pick: int) -> void:
	var dir := (c - a).normalized()
	var n := Vector3(out.x, 0, out.y)
	BuildingMesh3D.quad(st, [v.call(a + dir * 0.3 + out * 0.08, 2.95), v.call(c - dir * 0.3 + out * 0.08, 2.95), v.call(c - dir * 0.3 + out * 0.08, 3.6), v.call(a + dir * 0.3 + out * 0.08, 3.6)], n, SIGNS[pick % SIGNS.size()])

## A box of map `size` (x, y) centred at `at`, from `y0` up `tall`: four sides and a top.
static func box(st: SurfaceTool, v: Callable, at: Vector2, size: Vector2, y0: float, tall: float, col: Color) -> void:
	var s := size * 0.5
	var c := [at + Vector2(-s.x, -s.y), at + Vector2(s.x, -s.y), at + Vector2(s.x, s.y), at + Vector2(-s.x, s.y)]
	for i in 4:
		var e: Vector2 = c[(i + 1) % 4] - c[i]
		BuildingMesh3D.quad(st, [v.call(c[i], y0), v.call(c[(i + 1) % 4], y0), v.call(c[(i + 1) % 4], y0 + tall), v.call(c[i], y0 + tall)], Vector3(e.y, 0, -e.x).normalized(), col.darkened(0.08 * (i % 2)))
	BuildingMesh3D.quad(st, [v.call(c[0], y0 + tall), v.call(c[1], y0 + tall), v.call(c[2], y0 + tall), v.call(c[3], y0 + tall)], Vector3.UP, col.lightened(0.05))

## A flat upright rectangle facing `n`: centre `p`, half-width `half`, from y0 to y1.
static func _plane(st: SurfaceTool, v: Callable, p: Vector2, half: Vector2, y0: float, y1: float, n: Vector3, col: Color) -> void:
	BuildingMesh3D.quad(st, [v.call(p - half, y0), v.call(p + half, y0), v.call(p + half, y1), v.call(p - half, y1)], n, col)

## A slab sticking `depth` out of the wall at `p`: top, front and both ends.
static func _ledge(st: SurfaceTool, v: Callable, p: Vector2, half: Vector2, out: Vector2, y0: float, tall: float, depth: float, col: Color) -> void:
	var o := out * depth
	var n := Vector3(out.x, 0, out.y)
	var side := Vector3(half.x, 0, half.y).normalized()
	BuildingMesh3D.quad(st, [v.call(p - half, y0 + tall), v.call(p + half, y0 + tall), v.call(p + half + o, y0 + tall), v.call(p - half + o, y0 + tall)], Vector3.UP, col.lightened(0.04))
	BuildingMesh3D.quad(st, [v.call(p - half + o, y0), v.call(p + half + o, y0), v.call(p + half + o, y0 + tall), v.call(p - half + o, y0 + tall)], n, col)
	if depth < 0.3:
		return   # a window sill's ends are too small to see: half the triangles
	for end in [[p - half, -side], [p + half, side]]:
		var at: Vector2 = end[0]
		BuildingMesh3D.quad(st, [v.call(at, y0), v.call(at + o, y0), v.call(at + o, y0 + tall), v.call(at, y0 + tall)], end[1], col.darkened(0.1))
