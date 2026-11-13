## R3D5: which building footprint a map point stands in, from a coarse grid
## of the city's building polygons (only those the 3D view built).
## R3D7: which buildings stand between the camera and you (the Cutaway cuts
## exactly those, whole): footprints crossing a strip from you toward the
## camera that are tall enough there to hide you.
class_name Footprints
extends RefCounted

const CELL_M := 25.0
const STOREY_M := 3.6          # a storey with room to spare (BuildingMesh3D varies 2.9-3.5) plus roof
const CLEAR_M := 2.5           # half-width of the strip kept clear round your sight line
const REACH_M := 60.0
const SIGHT_RISE := 0.577      # tan 30: the sight line climbs this per metre toward the camera
const MAX_CUT := 16            # the shader's list

var _grid: Dictionary = {}   # Vector2i -> Array of [poly, tag, height]

static func build(city: CityData, centre: Vector2, radius: float) -> Footprints:
	var f := Footprints.new()
	for i in city.buildings.size():
		var b: Dictionary = city.buildings[i]
		var poly: PackedVector2Array = b["poly"]
		if poly.is_empty() or poly[0].distance_to(centre) > radius:
			continue
		var entry := [poly, i + 1, maxi(1, int(b.get("levels", 1))) * STOREY_M + 1.5]
		var box := _box(poly)
		for x in range(floori(box.position.x / CELL_M), floori(box.end.x / CELL_M) + 1):
			for y in range(floori(box.position.y / CELL_M), floori(box.end.y / CELL_M) + 1):
				f._grid.get_or_add(Vector2i(x, y), []).append(entry)
	return f

static func _box(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	return box

## The footprint containing `p`, or an empty polygon outdoors.
func at(p: Vector2) -> PackedVector2Array:
	for entry in _grid.get(Vector2i(floori(p.x / CELL_M), floori(p.y / CELL_M)), []):
		if Geometry2D.is_point_in_polygon(p, entry[0]):
			return entry[0]
	return PackedVector2Array()

## Tags of the buildings hiding `you` from a camera looking along `view` (map x/y).
func covering(you: Vector2, view: Vector2) -> PackedInt32Array:
	var back := -view.normalized()
	var side := Vector2(-back.y, back.x) * CLEAR_M
	var strip := PackedVector2Array([you - side, you + side, you + side + back * REACH_M, you - side + back * REACH_M])
	var out := PackedInt32Array()
	for entry in _near(_box(strip)):
		if out.size() < MAX_CUT and not out.has(entry[1]) and _hides(entry, strip, you, back):
			out.append(entry[1])
	return out

func _near(box: Rect2) -> Array:
	var seen: Array = []
	for x in range(floori(box.position.x / CELL_M), floori(box.end.x / CELL_M) + 1):
		for y in range(floori(box.position.y / CELL_M), floori(box.end.y / CELL_M) + 1):
			seen.append_array(_grid.get(Vector2i(x, y), []))
	return seen

## Crosses the strip, and is taller there than your sight line has climbed.
static func _hides(entry: Array, strip: PackedVector2Array, you: Vector2, back: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(you, entry[0]):
		return false   # the one you are in opens up by itself (Cutaway.room)
	for piece in Geometry2D.intersect_polygons(entry[0], strip):
		var nearest := INF
		for p in piece:
			nearest = minf(nearest, (p - you).dot(back))
		if entry[2] > 1.0 + maxf(nearest, 0.0) * SIGHT_RISE:
			return true
	return false
