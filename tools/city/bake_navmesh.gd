## City batch C3 part 2: bake the walkable area of the real city into navigation
## meshes. Walkable = everywhere that isn't inside a building or the river channel:
## streets, alleys, yards, parking lots and the gaps between buildings. The river
## is crossable only on bridges (boulevards over it). Baked in 8x8 tiles from
## clean merged obstacles (tools/city/nav_obstacles.py).
## Run: godot --headless --path . -s tools/city/bake_navmesh.gd
extends SceneTree

const TILES := 8
const AGENT_RADIUS := 0.4
const CELL_SIZE := 0.05   # fine grid: gaps between buildings can be under 1 m
const OUT_DIR := "res://data/city/nav/"
const OBSTACLES := "res://tools/city/nav_obstacles.json"   # from tools/city/nav_obstacles.py

func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OBSTACLES))
	var size: float = raw["size_m"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tile := size / TILES
	for f in DirAccess.get_files_at(OUT_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT_DIR + f))
	for tx in TILES:
		for ty in TILES:
			_bake_rect(Rect2(tx * tile, ty * tile, tile, tile), _to_polys(raw["obstacles"]["%d_%d" % [tx, ty]]))
	print("baked %d nav tiles, %d nav polygons, %d unbakeable leaf tiles" % [_saved, _polys, _failed])
	quit()

var _saved := 0
var _polys := 0
var _failed := 0

## Bake a rect; if the polygon partition fails (very dense blocks), split it in four.
func _bake_rect(rect: Rect2, obstacles: Array) -> void:
	var nav := _bake_tile(rect, obstacles)
	if nav.get_polygon_count() == 0 and rect.size.x > 40.0:
		var h := rect.size / 2
		for q in [Rect2(rect.position, h), Rect2(rect.position + Vector2(h.x, 0), h), Rect2(rect.position + Vector2(0, h.y), h), Rect2(rect.position + h, h)]:
			var near: Rect2 = q.grow(4.0)
			_bake_rect(q, obstacles.filter(func(o: PackedVector2Array) -> bool: return near.intersects(_bounds(o))))
		return
	if nav.get_polygon_count() == 0:   # last resort: simplify each obstacle to its convex hull
		nav = _bake_tile(rect, obstacles.map(func(o: PackedVector2Array) -> PackedVector2Array: return Geometry2D.convex_hull(o)))
	if nav.get_polygon_count() == 0:
		_failed += 1
		return
	_saved += 1
	_polys += nav.get_polygon_count()
	ResourceSaver.save(nav, OUT_DIR + "nav_%d_%d_%d.res" % [int(rect.position.x), int(rect.position.y), int(rect.size.x)])

func _to_polys(list: Array) -> Array:
	var out := []
	for o in list:
		var poly := PackedVector2Array()
		for p in o:
			poly.append(Vector2(p[0], p[1]))
		out.append(poly)
	return out

func _bake_tile(rect: Rect2, obstacles: Array) -> NavigationPolygon:
	var nav := NavigationPolygon.new()
	nav.agent_radius = AGENT_RADIUS
	nav.cell_size = CELL_SIZE
	var src := NavigationMeshSourceGeometryData2D.new()
	# exact tile rect: neighbours don't overlap; the map's edge-connection margin links them
	src.add_traversable_outline(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	for o in obstacles:
		src.add_obstruction_outline(o)
	NavigationServer2D.bake_from_source_geometry_data(nav, src)
	return nav

func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r
