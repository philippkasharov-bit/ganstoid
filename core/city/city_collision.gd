## City batch C3: solid buildings. Spatial hash over building footprints so
## movement can't pass through walls. Logic only: no drawing.
## Buildings are solid until interiors exist (last batch); then doors open them.
class_name CityCollision
extends RefCounted

const CELL := 48.0

var _grid := {}   # Vector2i -> Array[PackedVector2Array]

func _init(city: CityData) -> void:
	for b in city.buildings:
		var poly: PackedVector2Array = b["poly"]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				var key := Vector2i(cx, cy)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(poly)

## True if a body of `radius` at `p` would overlap a building.
func blocked(p: Vector2, radius: float = 0.4) -> bool:
	for poly in _grid.get(Vector2i((p / CELL).floor()), []):
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		for i in poly.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1]).distance_to(p) < radius:
				return true
	return false

## Move from `from` by `delta`, sliding along walls instead of stopping dead.
func slide(from: Vector2, delta: Vector2, radius: float = 0.4) -> Vector2:
	if blocked(from, radius):
		return from + delta   # already touching a wall (e.g. spawned on a doorstep): let them step away
	if not blocked(from + delta, radius):
		return from + delta
	if not blocked(from + Vector2(delta.x, 0), radius):
		return from + Vector2(delta.x, 0)
	if not blocked(from + Vector2(0, delta.y), radius):
		return from + Vector2(0, delta.y)
	return from
