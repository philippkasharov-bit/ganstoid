## R3D5: which building footprint a map point stands in, from a coarse grid
## of the city's building polygons (only those the 3D view built).
class_name Footprints
extends RefCounted

const CELL_M := 25.0

var _grid: Dictionary = {}   # Vector2i -> Array of PackedVector2Array

static func build(city: CityData, centre: Vector2, radius: float) -> Footprints:
	var f := Footprints.new()
	for b in city.buildings:
		var poly: PackedVector2Array = b["poly"]
		if poly.is_empty() or poly[0].distance_to(centre) > radius:
			continue
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		for x in range(floori(box.position.x / CELL_M), floori(box.end.x / CELL_M) + 1):
			for y in range(floori(box.position.y / CELL_M), floori(box.end.y / CELL_M) + 1):
				f._grid.get_or_add(Vector2i(x, y), []).append(poly)
	return f

## The footprint containing `p`, or an empty polygon outdoors.
func at(p: Vector2) -> PackedVector2Array:
	for poly in _grid.get(Vector2i(floori(p.x / CELL_M), floori(p.y / CELL_M)), []):
		if Geometry2D.is_point_in_polygon(p, poly):
			return poly
	return PackedVector2Array()
