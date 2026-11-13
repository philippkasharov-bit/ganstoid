## City batch C3: solid buildings. Spatial hash over building footprints so
## movement can't pass through walls. Logic only: no drawing.
## R3D14: buildings stay solid here; Indoors opens their doors (InteriorSolid).
class_name CityCollision
extends RefCounted

const CELL := 48.0
const LINE_STEP_M := 0.5

var _grid := {}   # Vector2i -> Array[PackedVector2Array]
var _owners := {}  # Vector2i -> Array[Dictionary]: the CityData building of each poly, same order

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
					_owners[key] = []
				_grid[key].append(poly)
				_owners[key].append(b)

## True if a body of `radius` at `p` would overlap a building.
func blocked(p: Vector2, radius: float = 0.4) -> bool:
	for poly in _grid.get(Vector2i((p / CELL).floor()), []):
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		for i in poly.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1]).distance_to(p) < radius:
				return true
	return false

## True if a body of `radius` can walk the straight line a -> b without touching
## a building (sampled every LINE_STEP_M: walls are far thicker than that).
func line_clear(a: Vector2, b: Vector2, radius: float = 0.4) -> bool:
	var n := maxi(1, int(ceil(a.distance_to(b) / LINE_STEP_M)))
	for i in range(1, n + 1):
		if blocked(a.lerp(b, float(i) / n), radius):
			return false
	return true

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

## R3D14: the CityData building whose footprint contains `p`, or {}.
func building_at(p: Vector2) -> Dictionary:
	var key := Vector2i((p / CELL).floor())
	var polys: Array = _grid.get(key, [])
	for i in polys.size():
		if Geometry2D.is_point_in_polygon(p, polys[i]):
			return _owners[key][i]
	return {}

## R3D14: the building whose wall a body of `radius` at `p` touches, or {}.
func building_touching(p: Vector2, radius: float) -> Dictionary:
	var key := Vector2i((p / CELL).floor())
	var polys: Array = _grid.get(key, [])
	for i in polys.size():
		var poly: PackedVector2Array = polys[i]
		if Geometry2D.is_point_in_polygon(p, poly):
			return _owners[key][i]
		for k in poly.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, poly[k], poly[k + 1]).distance_to(p) < radius:
				return _owners[key][i]
	return {}
