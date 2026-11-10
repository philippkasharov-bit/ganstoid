## City batch C3d: bake the PUBLIC navmesh civilians use: sidewalks, crosswalks,
## footpaths and parks ("walk_*" tiles) and alleys ("alley_*" tiles, own region so
## their travel cost can change). Private ground (yards, lots, gaps) is absent, and
## so is parkway grass (MP2b, cut out by nav_public.py).
## Input: tools/city/nav_public.json (tools/city/nav_public.py).
## Run: godot --headless --path . -s tools/city/bake_public_navmesh.gd
extends SceneTree

const TILES := 8
const AGENT_RADIUS := 0.4
const BORDER_M := 1.0   # under the 3 m margin nav_public.py leaves around each tile
const RADIUS_NUDGES: Array[float] = [0.03, 0.06, -0.03, 0.1]
const CELL_SIZE := 0.05   # must match CityNav and the full-city bake
const OUT_DIR := "res://data/city/nav_public/"
const SOURCE := "res://tools/city/nav_public.json"

var _saved := 0
var _polys := 0
var _failed := 0

func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var tile: float = float(raw["size_m"]) / TILES
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for f in DirAccess.get_files_at(OUT_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT_DIR + f))
	for layer in ["walk", "alley"]:
		for tx in TILES:
			for ty in TILES:
				var shapes: Array = raw[layer]["%d_%d" % [tx, ty]]
				if not shapes.is_empty():
					_bake_rect(layer, Rect2(tx * tile, ty * tile, tile, tile), shapes)
	print("baked %d public nav tiles, %d nav polygons, %d unbakeable leaf tiles" % [_saved, _polys, _failed])
	quit()

## Bake one rect; if the partition fails (dense blocks), split it in four.
func _bake_rect(layer: String, rect: Rect2, shapes: Array) -> void:
	var radius := AGENT_RADIUS
	var nav := _bake(rect, shapes, radius)
	# The convex partition sometimes fails on one degenerate corner; a slightly
	# different clearance moves that corner and the same ground bakes fine.
	for nudge in RADIUS_NUDGES:
		if nav.get_polygon_count() > 0 or not _has_area_inside(rect, shapes):
			break
		nav = _bake(rect, shapes, radius + nudge)
	if nav.get_polygon_count() == 0 and rect.size.x > 40.0 and _has_area_inside(rect, shapes):
		var h := rect.size / 2
		for q in [Rect2(rect.position, h), Rect2(rect.position + Vector2(h.x, 0), h), Rect2(rect.position + Vector2(0, h.y), h), Rect2(rect.position + h, h)]:
			var near: Rect2 = q.grow(4.0)
			_bake_rect(layer, q, shapes.filter(func(s: Dictionary) -> bool: return near.intersects(_bounds(s["outer"]))))
		return
	if nav.get_polygon_count() == 0:
		if _has_area_inside(rect, shapes):
			_failed += 1
			print("  unbakeable %s tile at %s" % [layer, rect])
		return
	_saved += 1
	_polys += nav.get_polygon_count()
	ResourceSaver.save(nav, OUT_DIR + "%s_%d_%d_%d.res" % [layer, int(rect.position.x), int(rect.position.y), int(rect.size.x)])

func _bake(rect: Rect2, shapes: Array, agent_radius: float) -> NavigationPolygon:
	var nav := NavigationPolygon.new()
	nav.agent_radius = agent_radius
	nav.cell_size = CELL_SIZE
	# Bake a little past the tile and throw that border away: the tile then ends
	# exactly on its edge with no agent-radius setback, so neighbouring tiles share
	# edges instead of facing each other across a 0.8 m gap (those gap links were
	# unreliable and split the district in two for civilians).
	nav.baking_rect = rect.grow(BORDER_M)
	nav.border_size = BORDER_M
	var src := NavigationMeshSourceGeometryData2D.new()
	for s in shapes:
		src.add_traversable_outline(_pts(s["outer"]))
		for hole in s["holes"]:
			src.add_obstruction_outline(_pts(hole))
	NavigationServer2D.bake_from_source_geometry_data(nav, src)
	return nav

## True if some shape really has ground inside rect (not just a bounding box that
## crosses it): more than 1 m2 of its outline, holes not counted.
func _has_area_inside(rect: Rect2, shapes: Array) -> bool:
	var box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	for s in shapes:
		if not rect.intersects(_bounds(s["outer"])):
			continue
		var area := 0.0
		for part in Geometry2D.intersect_polygons(_pts(s["outer"]), box):
			area += absf(_signed_area(part))
		for hole in s["holes"]:
			for part in Geometry2D.intersect_polygons(_pts(hole), box):
				area -= absf(_signed_area(part))
		if area > 1.0:
			return true
	return false

func _signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5

func _pts(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(Vector2(p[0], p[1]))
	return out

func _bounds(list: Variant) -> Rect2:
	var pts: PackedVector2Array = list if list is PackedVector2Array else _pts(list)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
