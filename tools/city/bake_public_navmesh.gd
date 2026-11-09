## City batch C3d: bake the PUBLIC navmesh civilians use: sidewalks, crosswalks,
## footpaths and parks ("walk_*" tiles) and alleys ("alley_*" tiles, own region so
## their travel cost can change). Private ground (yards, lots, gaps) is absent.
## Input: tools/city/nav_public.json (tools/city/nav_public.py).
## Run: godot --headless --path . -s tools/city/bake_public_navmesh.gd
extends SceneTree

const TILES := 8
const AGENT_RADIUS := 0.4
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
	var nav := _bake(rect, shapes)
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

func _bake(rect: Rect2, shapes: Array) -> NavigationPolygon:
	var nav := NavigationPolygon.new()
	nav.agent_radius = AGENT_RADIUS
	nav.cell_size = CELL_SIZE
	nav.baking_rect = rect   # clip exactly to the tile: neighbours never overlap
	var src := NavigationMeshSourceGeometryData2D.new()
	for s in shapes:
		src.add_traversable_outline(_pts(s["outer"]))
		for hole in s["holes"]:
			src.add_obstruction_outline(_pts(hole))
	NavigationServer2D.bake_from_source_geometry_data(nav, src)
	return nav

func _has_area_inside(rect: Rect2, shapes: Array) -> bool:
	for s in shapes:
		if rect.intersects(_bounds(s["outer"])):
			return true
	return false

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
