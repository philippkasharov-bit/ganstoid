## OPT1: the whole city sorted into the 3D view's chunks, once, so a chunk
## can be built from its own slice of the data (a small CityData and
## CityReal holding only what touches it) instead of scanning the city.
## Lines and outlines go to every chunk they touch (CityMesh3D drops what
## falls in a neighbour); points go to the one chunk they stand in.
class_name ChunkIndex3D
extends RefCounted

var origin := Vector2.ZERO
var _cells: Dictionary = {}   # Vector2i -> [CityData, CityReal]

static func build(city: CityData, real: CityReal, at_origin: Vector2) -> ChunkIndex3D:
	var ix := ChunkIndex3D.new()
	ix.origin = at_origin
	for i in city.buildings.size():
		city.buildings[i]["tag"] = i + 1   # R3D7: the Cutaway knows a building by its city index
		ix._spread(city.buildings[i]["poly"], func(c: Array) -> void: c[0].buildings.append(city.buildings[i]))
	for r in city.roads:
		ix._spread(r["pts"], func(c: Array) -> void: c[0].roads.append(r))
	for a in city.areas:
		ix._spread(a["poly"], func(c: Array) -> void: c[0].areas.append(a))
	for w in city.tree_wells:
		ix._cell(w)[0].tree_wells.append(w)
	for cw in city.crosswalks:
		ix._cell(cw["c"])[0].crosswalks.append(cw)
	for d in city.driveways:
		ix._cell(d["c"])[0].driveways.append(d)
	for lot in real.lots:
		ix._spread(lot["poly"], func(c: Array) -> void: c[1].lots.append(lot))
	for s in real.surfaces:
		ix._spread(s["poly"], func(c: Array) -> void: c[1].surfaces.append(s))
	for b in real.barriers:
		ix._spread(b["pts"], func(c: Array) -> void: c[1].barriers.append(b))
	for c in real.crossings:
		ix._spread(c["pts"], func(cell: Array) -> void: cell[1].crossings.append(c))
	for p in real.points:
		ix._cell(p["p"])[1].points.append(p)
	for t in real.trees:
		ix._cell(t)[1].trees.append(t)
	return ix

func key_of(p: Vector2) -> Vector2i:
	return Vector2i(((p - origin) / CityMesh3D.CHUNK_M).floor())

## The chunk's square on the map.
func rect_of(key: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(key) * CityMesh3D.CHUNK_M, Vector2.ONE * CityMesh3D.CHUNK_M)

## [CityData, CityReal] holding what touches chunk `key` (empty ones where nothing is).
func slice(key: Vector2i) -> Array:
	return _cells.get(key, [CityData.new(), CityReal.new()])

func _cell(p: Vector2) -> Array:
	var k := key_of(p)
	if not _cells.has(k):
		_cells[k] = [CityData.new(), CityReal.new()]
	return _cells[k]

## Calls `add` with every chunk the box round `pts` touches.
func _spread(pts: PackedVector2Array, add: Callable) -> void:
	if pts.is_empty():
		return
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	var lo := key_of(box.position)
	var hi := key_of(box.end)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var k := Vector2i(x, y)
			if not _cells.has(k):
				_cells[k] = [CityData.new(), CityReal.new()]
			add.call(_cells[k])
