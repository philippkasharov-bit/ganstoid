## City batch C3 part 2: pathfinding over the real city. Walkable = streets,
## alleys, yards, lots and every gap between buildings; buildings and the river
## channel (except bridges) are not. Baked tiles (tools/city/bake_navmesh.gd) are
## STREAMED: only tiles near the focus point are loaded, because syncing the whole
## 6 km city at once takes minutes in Godot 4.3. Logic only: no drawing.
class_name CityNav
extends RefCounted

const NAV_DIRS := {"full": "res://data/city/nav/", "public": "res://data/city/nav_public/"}   # public = civilians only (C3d)
const CELL_SIZE := 0.05   # must match the bake

var map: RID
var radius: float
var nav_dir: String
## Travel cost of alley regions (public layer only). Civilians avoid alleys (>1),
## more so at night; dark-route NPCs use 1.0. Changing it re-costs loaded tiles.
var alley_cost := 1.0:
	set(v):
		alley_cost = v
		for f in _loaded:
			if f.begins_with("alley_"):
				NavigationServer2D.region_set_travel_cost(_loaded[f], v)
		# (loaded regions pick the new cost up at the map's next background sync)
var _ready_latched := false   # true from the first successful is_ready() until the tiles change
var _tiles := {}    # file -> Rect2
var _loaded := {}   # file -> region RID
var _changed_at := -1   # AR0 (Godot 4.7): map iteration id when tiles last changed; the map syncs in the background

## layer "full": everywhere walkable (locals, crew, player). "public": sidewalks,
## crosswalks, paths, parks and alleys only (civilians).
func _init(focus_point: Vector2, load_radius: float = 700.0, layer: String = "full", alley_cost_value: float = 1.0) -> void:
	radius = load_radius
	alley_cost = alley_cost_value
	nav_dir = NAV_DIRS[layer]
	map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer2D.map_set_edge_connection_margin(map, 2.0)
	NavigationServer2D.map_set_active(map, true)
	for f in DirAccess.get_files_at(nav_dir):
		if f.ends_with(".res"):
			var p := f.trim_suffix(".res").split("_")   # <nav|walk|alley>_<x>_<y>_<size>
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
			NavigationServer2D.region_set_navigation_polygon(r, load(nav_dir + f))
			if f.begins_with("alley_"):
				NavigationServer2D.region_set_travel_cost(r, alley_cost)
			_loaded[f] = r
			changed = true
		elif not want and _loaded.has(f):
			NavigationServer2D.free_rid(_loaded[f])
			_loaded.erase(f)
			changed = true
	if changed:
		_ready_latched = false
		NavigationServer2D.map_set_active(map, true)
		_changed_at = NavigationServer2D.map_get_iteration_id(map)
	return changed

## True once the background sync has picked up every tile loaded so far: each
## region is built, the map has synced since the change, and every loaded tile
## answers a closest-point probe from inside itself. Until then paths and
## closest points can come back empty.
func is_ready() -> bool:
	if _ready_latched:
		return true   # asked every frame and every sim tick: the probes below cost ~1 ms per tile
	for f in _loaded:
		if NavigationServer2D.region_get_iteration_id(_loaded[f]) == 0:
			return false
	if NavigationServer2D.map_get_iteration_id(map) <= _changed_at:
		return false
	for f in _loaded:
		var t: Rect2 = _tiles[f]
		if NavigationServer2D.map_get_closest_point(map, t.get_center()).distance_to(t.get_center()) > t.size.x * 0.75:
			return false
	_ready_latched = true
	# Synced: put the map to sleep. An active map costs ~1 ms of every physics
	# frame even when nothing changes; a sleeping one still answers path and
	# closest-point queries. focus() wakes it when tiles change.
	NavigationServer2D.map_set_active(map, false)
	return true

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
