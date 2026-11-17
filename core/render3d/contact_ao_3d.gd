## VS2-0: baked contact shading on the ground. A soft dark band round every
## building's foot and along both sides of walls, fences and hedges, built
## with each chunk (CityMesh3D.ao_tool) and drawn as one multiply-blended mesh
## per chunk: dark at the wall, fading to nothing a little way out. It darkens
## whatever ground lies under it (grass, sidewalk, asphalt), so nothing in the
## chunk mesh needs a second colour. The vertex colour is the shade (1 = none).
## The compatibility renderer (the album) has no SSAO, and SSAO is faint from
## the game's high camera; this reads the same in both.
class_name ContactAO3D
extends RefCounted

const LIFT := 0.06          # above roads (0.04), lots and sidewalks; below the kerb top
const WALL_M := 1.3         # how far the shade reaches from a building
const WALL_SHADE := 0.56    # at the wall foot
const LINE_M := 0.55        # from a wall, fence or hedge
const LINE_SHADE := 0.74
const STRENGTH := 1.0       # 0 turns it off (the admin "AO" look uses 1)

const SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float strength = 1.0;
void fragment() {
	ALBEDO = mix(vec3(1.0), COLOR.rgb, strength);
	ALPHA = 1.0;   // drawn with the see-through things, after the ground (without it, the ground drawn later covers it)
}
"""

static var _mat: ShaderMaterial

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("strength", STRENGTH)
		_mat.render_priority = -1   # before other see-through things (graffiti, glass)
	return _mat

## A building footprint: a band outward from every wall, with the convex corners filled.
static func building(m: CityMesh3D, poly: PackedVector2Array) -> void:
	poly = CityMesh3D._open(poly)
	if poly.size() < 3:
		return
	var st := m.ao_tool(poly[0])
	if st == null:
		return
	var ccw := CityMesh3D._ccw(poly)
	var outs: Array[Vector2] = []
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		outs.append((Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)).normalized() if e.length() > 0.01 else Vector2.ZERO)
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var o: Vector2 = outs[i]
		if o == Vector2.ZERO:
			continue
		_band(st, m, a, c, o * WALL_M, WALL_SHADE)
		var prev: Vector2 = outs[(i - 1 + poly.size()) % poly.size()]
		if prev != Vector2.ZERO and prev.cross(o) * (1.0 if ccw else -1.0) < 0.0:   # a convex corner: fill the wedge between the two bands
			_tri(st, m, a, a + prev * WALL_M, a + o * WALL_M, WALL_SHADE)

## A wall, fence or hedge `half_w` thick along `pts`: a band either side.
static func line(m: CityMesh3D, pts: PackedVector2Array, half_w: float) -> void:
	if pts.size() < 2:
		return
	var st := m.ao_tool(pts[0])
	if st == null:
		return
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if a.distance_to(b) < 0.05:
			continue
		var n := (b - a).orthogonal().normalized()
		for side in [1.0, -1.0]:
			var foot: Vector2 = n * half_w * side
			_band(st, m, a + foot, b + foot, n * LINE_M * side, LINE_SHADE)

## A strip a..b, shade `dark` on that edge, none at a+out..b+out.
static func _band(st: SurfaceTool, m: CityMesh3D, a: Vector2, b: Vector2, out: Vector2, dark: float) -> void:
	var d := Color(dark, dark, dark)
	var pts := [m._v(a, LIFT), m._v(b, LIFT), m._v(b + out, LIFT), m._v(a + out, LIFT)]
	var cols := [d, d, Color.WHITE, Color.WHITE]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(cols[k])
		st.add_vertex(pts[k])

## A corner wedge: dark at the corner, none along the outer edge.
static func _tri(st: SurfaceTool, m: CityMesh3D, corner: Vector2, p: Vector2, q: Vector2, dark: float) -> void:
	st.set_color(Color(dark, dark, dark))
	st.add_vertex(m._v(corner, LIFT))
	st.set_color(Color.WHITE)
	st.add_vertex(m._v(p, LIFT))
	st.add_vertex(m._v(q, LIFT))
