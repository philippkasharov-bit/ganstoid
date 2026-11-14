## B2: tags sprayed on the city. Shops, works and garages get them most,
## apartments sometimes, houses rarely; a tag goes on one long wall, low
## down where a writer reaches, sized and picked (four tags in the atlas)
## by a hash of the building, so a wall keeps its tag every run. Decals sit
## between the wall and the window glass, so glass covers them. Their own
## Cutaway material (decal_on), with the building's tag in UV.y so a cut
## building loses its graffiti with it.
class_name Graffiti3D
extends RefCounted

const ATLAS := "res://art/textures/graffiti.png"
const TAGS := 4
const SHARE := {"commercial": 38, "industrial": 55, "garage": 45, "apartments": 16, "house": 3, "civic": 10}   # percent of buildings
const OUT_M := 0.04
const MIN_WALL_M := 4.0
const WALL_SHARE := 18     # percent of free-standing wall segments

static var _material: ShaderMaterial

## The graffiti material (made once; Cutaway updates it with the rest).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = Cutaway.material()
		_material.set_shader_parameter("decal_on", true)
		var img := Image.load_from_file(ATLAS) if FileAccess.file_exists(ATLAS) else null
		if img != null:
			img.generate_mipmaps()
			_material.set_shader_parameter("decal_tex", ImageTexture.create_from_image(img))
	return Cutaway.keep(_material)

## Maybe a tag on building `b` (CityData dict) with Cutaway tag `tag`.
static func on_building(m: CityMesh3D, b: Dictionary, tag: int) -> void:
	var roll := absi(hash(b.get("id", b["poly"][0])))
	if roll % 100 >= int(SHARE.get(b.get("kind", "house"), 0)):
		return
	var poly := CityMesh3D._open(b["poly"])
	var i := (roll / 100) % poly.size()
	for tries in poly.size():   # the first wall long enough, from a hashed start
		var a := poly[(i + tries) % poly.size()]
		var c := poly[(i + tries + 1) % poly.size()]
		if a.distance_to(c) >= MIN_WALL_M:
			var e := c - a
			var out := (Vector2(e.y, -e.x) if CityMesh3D._ccw(poly) else Vector2(-e.y, e.x)).normalized()
			_stamp(m, a, c, out, tag, roll)
			return

## B2: maybe a tag on a free-standing wall (CityReal barrier points): no windows, so bigger.
static func on_wall(m: CityMesh3D, pts: PackedVector2Array) -> void:
	for i in pts.size() - 1:
		var roll := absi(hash(pts[i]))
		var a := pts[i]
		var c := pts[i + 1]
		if roll % 100 < WALL_SHARE and a.distance_to(c) >= MIN_WALL_M:
			var side := (c - a).normalized().orthogonal() * (1.0 if roll % 2 == 0 else -1.0)
			_stamp(m, a + side * 0.11, c + side * 0.11, side, 0, roll, 2.8, 0.25)

## One tag on the wall a..c facing `out`, at most `widest` wide, its foot `foot` off the ground.
static func _stamp(m: CityMesh3D, a: Vector2, c: Vector2, out: Vector2, tag: int, roll: int, widest: float = 2.0, foot: float = 0.1) -> void:
	var st := m.decal_tool(a)
	if st == null:
		return
	var length := a.distance_to(c)
	var w := minf(widest - float(roll % 5) / 10.0, length - 1.0)   # under the window sills on buildings
	var dir := (c - a) / length
	var mid := a + dir * (0.5 + float((roll >> 4) % 100) / 100.0 * (length - w - 1.0) + w * 0.5) + out * OUT_M
	var half := dir * w * 0.5
	var h := w * 0.42   # the atlas cell is 2:1; a little squashed keeps it under the sills
	var cell := float((roll >> 8) % TAGS)
	var fade := Color.WHITE.darkened(float((roll >> 12) % 30) / 100.0)   # older tags have faded
	var corners := [[mid - half, foot, Vector2(0, cell + 1)], [mid + half, foot, Vector2(1, cell + 1)], [mid + half, foot + h, Vector2(1, cell)], [mid - half, foot + h, Vector2(0, cell)]]
	st.set_color(fade)
	st.set_normal(Vector3(out.x, 0, out.y))
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(0, tag))
		st.set_uv2(Vector2(corners[k][2].x, corners[k][2].y / TAGS))
		st.add_vertex(m._v(corners[k][0], corners[k][1]))
