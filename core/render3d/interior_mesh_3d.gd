## R3D9: the inside of the building you walk into, built when you enter (the
## city has 21k shells; only the one you are in gets an inside). The
## footprint is split into rooms in its own frame (along its longest wall),
## the splits become inner walls with a doorway each, every room gets a
## floor by what it is (wood living room, tiled kitchen and bathroom, carpet
## bedrooms; shop floor and stock room; bare concrete for industry) and its
## furniture as boxes against the walls, kept clear of doorways.
class_name InteriorMesh3D
extends RefCounted

const WALL_H := 2.5
const WALL_T := 0.12
const DOOR_GAP := 0.95
const MIN_ROOM := 2.6
const TARGET_M2 := 16.0
const FLOOR_Y := 0.03
const WALL_COL := Color("e9e2d3")
const FLOORS := {"living": Color("9b7350"), "kitchen": Color("d9d4c8"), "bath": Color("cfe0e3"), "bed": Color("8c8f9c"),
	"shop": Color("c8c3b8"), "stock": Color("a19a8c"), "work": Color("8f8f8a")}
## name, [width along the wall, depth, height], colour
const FURNITURE := {
	"living": [["sofa", [2.0, 0.9, 0.8], Color("5b6b8a")], ["tv", [1.4, 0.45, 1.0], Color("2b2b2e")], ["table", [1.0, 0.6, 0.45], Color("7a5a3c")], ["shelf", [1.0, 0.4, 1.8], Color("6e5137")]],
	"kitchen": [["fridge", [0.75, 0.7, 1.8], Color("e8eaeb")], ["stove", [0.7, 0.65, 0.9], Color("cfd2d4")], ["counter", [1.4, 0.65, 0.9], Color("b9a27e")], ["counter", [1.4, 0.65, 0.9], Color("b9a27e")], ["table", [1.2, 0.8, 0.75], Color("8a6a48")]],
	"bath": [["tub", [1.6, 0.75, 0.55], Color("f4f4f2")], ["toilet", [0.45, 0.65, 0.75], Color("f4f4f2")], ["sink", [0.6, 0.45, 0.85], Color("f4f4f2")]],
	"bed": [["bed", [1.6, 2.0, 0.55], Color("a34b4b")], ["drawers", [1.0, 0.5, 1.0], Color("6e5137")], ["wardrobe", [1.2, 0.6, 2.0], Color("5f4630")]],
	"shop": [["shelf", [2.4, 0.6, 1.7], Color("b0b6ba")], ["shelf", [2.4, 0.6, 1.7], Color("b0b6ba")], ["counter", [2.0, 0.7, 1.0], Color("6b4a33")], ["fridge", [1.6, 0.7, 2.0], Color("dfe6ea")]],
	"stock": [["crates", [1.2, 1.0, 1.2], Color("9c7a4e")], ["shelf", [2.0, 0.6, 2.0], Color("8d8f91")]],
	"work": [["bench", [2.0, 0.8, 0.95], Color("7d6a50")], ["crates", [1.2, 1.0, 1.2], Color("9c7a4e")], ["drums", [0.6, 0.6, 0.9], Color("3f5f7a")]],
}

var _st := SurfaceTool.new()
var _base := Vector2.ZERO      # map point at the frame's origin
var _angle := 0.0              # the frame's turn (its longest wall)
var _origin := Vector2.ZERO    # map point at 3D (0, 0, 0)
var _doors: Array[Vector2] = []   # doorway middles, in the frame

## The inside of building `b` (CityData dict) as one mesh, in the 3D view's space.
static func build(b: Dictionary, origin: Vector2, material: Material) -> MeshInstance3D:
	var im := InteriorMesh3D.new()
	im._origin = origin
	var poly := BuildingMesh3D._open(b["poly"])
	im._frame(poly)
	var local := PackedVector2Array()
	for p in poly:
		local.append((p - im._base).rotated(-im._angle))
	var rng := RandomNumberGenerator.new()
	rng.seed = String(b["id"]).hash() + 7
	im._st.begin(Mesh.PRIMITIVE_TRIANGLES)
	im._st.set_uv(Vector2.ZERO)
	var rooms := im._split(Footprints._box(local), rng, 0, local)
	var kinds := _kinds(rooms, String(b["kind"]))
	for i in rooms.size():
		im._floor(rooms[i], local, FLOORS[kinds[i]])
	for i in rooms.size():
		im._furnish(rooms[i], local, kinds[i], rng)
	var mi := MeshInstance3D.new()
	mi.mesh = im._st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _frame(poly: PackedVector2Array) -> void:
	var best := 0.0
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best:
			best = e.length()
			_angle = e.angle()
	_base = poly[0]

func _v(local: Vector2, h: float) -> Vector3:
	var p := _base + local.rotated(_angle) - _origin
	return Vector3(p.x, h, p.y)

## Rooms by splitting the footprint's box, longest side first; each split is an inner wall.
func _split(r: Rect2, rng: RandomNumberGenerator, depth: int, local: PackedVector2Array) -> Array[Rect2]:
	var along_x := r.size.x >= r.size.y
	var length := r.size.x if along_x else r.size.y
	if r.get_area() < TARGET_M2 * 1.6 or length < MIN_ROOM * 2.0 or depth > 4:
		return [r]
	var cut := length * rng.randf_range(0.38, 0.62)
	var a := Rect2(r.position, Vector2(cut, r.size.y) if along_x else Vector2(r.size.x, cut))
	var b := Rect2(r.position + (Vector2(cut, 0) if along_x else Vector2(0, cut)), r.size - (Vector2(cut, 0) if along_x else Vector2(0, cut)))
	var from := a.end if not along_x else Vector2(a.end.x, r.position.y)
	var to := Vector2(r.position.x, a.end.y) if not along_x else a.end
	_wall(from, to, local, rng)
	var out: Array[Rect2] = []
	out.append_array(_split(a, rng, depth + 1, local))
	out.append_array(_split(b, rng, depth + 1, local))
	return out

## An inner wall along a-b, kept inside the footprint, with one doorway in its longest piece.
func _wall(a: Vector2, b: Vector2, local: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var pieces := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), local)
	var longest := -1
	for i in pieces.size():
		if longest < 0 or pieces[i][0].distance_to(pieces[i][1]) > pieces[longest][0].distance_to(pieces[longest][1]):
			longest = i
	for i in pieces.size():
		var p: PackedVector2Array = pieces[i]
		var length := p[0].distance_to(p[1])
		if i == longest and length > DOOR_GAP + 0.6:
			var t := rng.randf_range(0.3 + DOOR_GAP * 0.5, length - 0.3 - DOOR_GAP * 0.5) / length
			var dir := (p[1] - p[0]) / length
			var mid := p[0].lerp(p[1], t)
			_doors.append(mid)
			_slab(p[0], mid - dir * DOOR_GAP * 0.5)
			_slab(mid + dir * DOOR_GAP * 0.5, p[1])
		else:
			_slab(p[0], p[1])

func _slab(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < 0.05:
		return
	var n := (b - a).normalized().orthogonal() * WALL_T * 0.5
	_cuboid([a - n, b - n, b + n, a + n], 0.0, WALL_H, WALL_COL)

func _floor(r: Rect2, local: PackedVector2Array, col: Color) -> void:
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	_st.set_color(col)
	_st.set_normal(Vector3.UP)
	for piece in Geometry2D.intersect_polygons(box, local):
		var tris := Geometry2D.triangulate_polygon(piece)
		for k in tris:
			_st.add_vertex(_v(piece[k], FLOOR_Y))

## What each room is: houses get living, kitchen, bath, bedrooms; shops a floor and a stock room.
static func _kinds(rooms: Array[Rect2], kind: String) -> Array[String]:
	var order := range(rooms.size())
	order.sort_custom(func(a: int, b: int) -> bool: return rooms[a].get_area() > rooms[b].get_area())
	var out: Array[String] = []
	out.resize(rooms.size())
	for rank in order.size():
		var i: int = order[rank]
		if kind in ["industrial", "garage"]:
			out[i] = "work"
		elif kind in ["commercial", "civic", "building"]:
			out[i] = "shop" if rank == 0 else "stock"
		elif rank == 0:
			out[i] = "living"
		elif rank == order.size() - 1 and order.size() > 2:
			out[i] = "bath"
		elif rank == 1:
			out[i] = "kitchen"
		else:
			out[i] = "bed"
	return out

## Furniture against the room's walls: inside the footprint, not on another piece, not in a doorway.
func _furnish(r: Rect2, local: PackedVector2Array, kind: String, rng: RandomNumberGenerator) -> void:
	var placed: Array[Rect2] = []
	for item in FURNITURE[kind]:
		for attempt in 8:
			var spot := _against_wall(r.grow(-WALL_T), item[1], rng)
			if _fits(spot, local, placed):
				placed.append(spot)
				var c := [spot.position, Vector2(spot.end.x, spot.position.y), spot.end, Vector2(spot.position.x, spot.end.y)]
				_cuboid(c, FLOOR_Y, item[1][2], item[2])
				break

static func _against_wall(r: Rect2, size: Array, rng: RandomNumberGenerator) -> Rect2:
	var side := rng.randi() % 4
	var w: float = size[0]
	var d: float = size[1]
	var ext := Vector2(w, d) if side % 2 == 0 else Vector2(d, w)
	var free := r.size - ext
	if free.x < 0.0 or free.y < 0.0:
		return Rect2()
	var at := Vector2(rng.randf() * free.x, rng.randf() * free.y)
	match side:
		0: at.y = 0.0
		1: at.x = free.x
		2: at.y = free.y
		3: at.x = 0.0
	return Rect2(r.position + at, ext)

func _fits(spot: Rect2, local: PackedVector2Array, placed: Array[Rect2]) -> bool:
	if not spot.has_area():
		return false
	for p in [spot.position, Vector2(spot.end.x, spot.position.y), spot.end, Vector2(spot.position.x, spot.end.y)]:
		if not Geometry2D.is_point_in_polygon(p, local):
			return false
	for other in placed:
		if other.grow(0.1).intersects(spot):
			return false
	for door in _doors:
		if spot.grow(0.7).has_point(door):
			return false
	return true

## A box on corners c (in the frame, in order) from y0 up by h: four sides and a top.
func _cuboid(c: Array, y0: float, h: float, col: Color) -> void:
	for i in 4:
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % 4]
		var e := (b - a).rotated(_angle)
		var shade := col.darkened(0.08 * (i % 2))
		BuildingMesh3D.quad(_st, [_v(a, y0), _v(b, y0), _v(b, y0 + h), _v(a, y0 + h)], Vector3(e.y, 0, -e.x).normalized(), shade)
	BuildingMesh3D.quad(_st, [_v(c[0], y0 + h), _v(c[1], y0 + h), _v(c[2], y0 + h), _v(c[3], y0 + h)], Vector3.UP, col.lightened(0.06))
