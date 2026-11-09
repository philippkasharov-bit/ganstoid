## City batch C3 part 2: pathfinding over the real city. Walkable = streets,
## alleys, yards, lots and every gap between buildings; buildings and the river
## channel (except bridges) are not. Baked tiles (tools/city/bake_navmesh.gd) are
## STREAMED: only tiles near the focus point are loaded, because syncing the whole
## 6 km city at once takes minutes in Godot 4.3. Logic only: no drawing.
class_name CityNav
extends RefCounted

const NAV_DIR := "res://data/city/nav/"
const CELL_SIZE := 0.05   # must match the bake

var map: RID
var radius: float
var _tiles := {}    # file -> Rect2
var _loaded := {}   # file -> region RID

func _init(focus_point: Vector2, load_radius: float = 700.0) -> void:
	radius = load_radius
	map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer2D.map_set_edge_connection_margin(map, 2.0)
	NavigationServer2D.map_set_active(map, true)
	for f in DirAccess.get_files_at(NAV_DIR):
		if f.ends_with(".res"):
			var p := f.trim_suffix(".res").split("_")   # nav_<x>_<y>_<size>
			_tiles[f] = Rect2(float(p[1]), float(p[2]), float(p[3]), float(p[3]))
	focus(focus_point)

## Load tiles within `radius` of p, unload the rest. Returns true if anything changed.
func focus(p: Vector2) -> bool:
	var area := Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2)
	var changed := false
	for f in _tiles:
		var want: bool = area.intersects(_tiles[f])
		if want and not _loaded.has(f):
			var r := NavigationServer2D.region_create()
			NavigationServer2D.region_set_map(r, map)
			NavigationServer2D.region_set_navigation_polygon(r, load(NAV_DIR + f))
			_loaded[f] = r
			changed = true
		elif not want and _loaded.has(f):
			NavigationServer2D.free_rid(_loaded[f])
			_loaded.erase(f)
			changed = true
	if changed:
		NavigationServer2D.map_force_update(map)
	return changed

func loaded_count() -> int:
	return _loaded.size()

func tile_count() -> int:
	return _tiles.size()

## Walkable path from `from` to `to` inside the loaded area.
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return NavigationServer2D.map_get_path(map, from, to, true)

func closest(p: Vector2) -> Vector2:
	return NavigationServer2D.map_get_closest_point(map, p)

func release() -> void:
	for r in _loaded.values():
		NavigationServer2D.free_rid(r)
	NavigationServer2D.free_rid(map)
