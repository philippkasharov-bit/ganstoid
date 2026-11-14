## R3D9/R3D14: the inside of the building you are in, drawn from the sim's
## InteriorLayout (so what you bump into is what you see): a floor per room
## by what it is (wood living room, tiled kitchen and bathroom, carpet
## bedrooms; shop floor and stock room; bare concrete for industry), inner
## walls with their doorways, and furniture as boxes. Built as you enter
## (the city has 21k shells; only the one you are in gets an inside).
class_name InteriorMesh3D
extends RefCounted

const WALL_H := 2.5
const FLOOR_Y := 0.03
const WALL_COL := Color("e9e2d3")
const FLOORS := {"living": Color("9b7350"), "kitchen": Color("d9d4c8"), "bath": Color("cfe0e3"), "bed": Color("8c8f9c"),
	"shop": Color("c8c3b8"), "stock": Color("a19a8c"), "work": Color("8f8f8a")}
const FLOOR_OF := {"living": SurfaceDetail.WOOD, "kitchen": SurfaceDetail.TILE, "bath": SurfaceDetail.TILE, "shop": SurfaceDetail.TILE,
	"stock": SurfaceDetail.SIDEWALK, "work": SurfaceDetail.SIDEWALK, "bed": SurfaceDetail.CARPET}   # TX1/TX3
const COLOURS := {"sofa": Color("5b6b8a"), "tv": Color("2b2b2e"), "table": Color("7a5a3c"), "shelf": Color("6e5137"),
	"fridge": Color("e8eaeb"), "stove": Color("cfd2d4"), "counter": Color("b9a27e"), "tub": Color("f4f4f2"), "toilet": Color("f4f4f2"),
	"sink": Color("f4f4f2"), "bed": Color("a34b4b"), "drawers": Color("6e5137"), "wardrobe": Color("5f4630"), "crates": Color("9c7a4e"),
	"bench": Color("7d6a50"), "drums": Color("3f5f7a")}

var _st := SurfaceTool.new()
var _l: InteriorLayout
var _origin := Vector2.ZERO    # map point at 3D (0, 0, 0)

## The inside of building `b` (CityData dict) as one mesh, in the 3D view's space.
## `tag` > 0 lets the Cutaway cut it with its building (an inside seen through a cut wall).
static func build(b: Dictionary, origin: Vector2, material: Material, tag: int = 0) -> MeshInstance3D:
	var im := InteriorMesh3D.new()
	im._origin = origin
	im._l = InteriorLayout.of(b)
	im._st.begin(Mesh.PRIMITIVE_TRIANGLES)
	im._st.set_uv(Vector2(0, tag))
	for i in im._l.rooms.size():
		im._floor(im._l.rooms[i], SurfaceDetail.mark(FLOORS[im._l.kinds[i]], FLOOR_OF.get(im._l.kinds[i], SurfaceDetail.NONE)))
	for i in range(0, im._l.walls.size() - 1, 2):
		im._slab(im._l.to_local(im._l.walls[i]), im._l.to_local(im._l.walls[i + 1]))
	for f in im._l.furniture:
		var shade: Color = COLOURS.get(f["name"], Color.GRAY)
		im._cuboid(Array(InteriorLayout.corners(f["rect"])), FLOOR_Y, f["h"], shade)
	var mi := MeshInstance3D.new()
	mi.mesh = im._st.commit()
	mi.set_meta("walls", InteriorSolid.build(im._l, false))   # R3D11/R3D14: what blocks sight inside (front door open)
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _v(local: Vector2, h: float) -> Vector3:
	var p := _l.to_map(local) - _origin
	return Vector3(p.x, h, p.y)

func _slab(a: Vector2, b: Vector2) -> void:
	var n := (b - a).normalized().orthogonal() * InteriorLayout.WALL_T * 0.5
	_cuboid([a - n, b - n, b + n, a + n], 0.0, WALL_H, WALL_COL)

func _floor(r: Rect2, col: Color) -> void:
	_st.set_color(col)
	_st.set_normal(Vector3.UP)
	for piece in Geometry2D.intersect_polygons(InteriorLayout.corners(r), _l.local):
		var tris := Geometry2D.triangulate_polygon(piece)
		for k in tris:
			_st.add_vertex(_v(piece[k], FLOOR_Y))

## A box on corners c (in the frame, in order) from y0 up by h: four sides and a top.
func _cuboid(c: Array, y0: float, h: float, col: Color) -> void:
	for i in 4:
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % 4]
		var e := (b - a).rotated(_l.angle)
		var shade := col.darkened(0.08 * (i % 2))
		BuildingMesh3D.quad(_st, [_v(a, y0), _v(b, y0), _v(b, y0 + h), _v(a, y0 + h)], Vector3(e.y, 0, -e.x).normalized(), shade)
	BuildingMesh3D.quad(_st, [_v(c[0], y0 + h), _v(c[1], y0 + h), _v(c[2], y0 + h), _v(c[3], y0 + h)], Vector3.UP, col.lightened(0.06))
