## Uniform grid spatial hash for proximity queries (player-NPC encounter
## detection, later crime-witness-radius checks) — O(entities in nearby
## cells) instead of O(all entities) per query.
##
## Zomboid precedent for the *shape* of this (confirmed): its world is
## partitioned into fixed-size cells (IsoCell in its Lua modding API) for
## map streaming. This mirrors that pattern for simulation queries, not
## loading. Whether Zomboid's own simulation detail actually drops for
## distant cells is NOT confirmed by anything I found — that's a Ganstoid
## design choice (see world_driver.gd note on simulation LOD), not a cited
## fact about Zomboid's engine.
class_name SpatialIndex
extends RefCounted

## 128 m buckets hold several real city blocks' worth of doors per cell —
## coarse enough that most proximity queries touch one cell, fine enough
## that "nearby" doesn't mean "half the city."
const CELL_SIZE := 128.0

var _cells: Dictionary = {}       # Vector2i -> Dictionary[StringName, bool]
var _entity_cell: Dictionary = {} # StringName -> Vector2i (so remove/update don't need position)

func _cell_coord(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))

func insert(id: StringName, position: Vector2) -> void:
	var coord := _cell_coord(position)
	if not _cells.has(coord):
		_cells[coord] = {}
	_cells[coord][id] = true
	_entity_cell[id] = coord

func remove(id: StringName) -> void:
	if not _entity_cell.has(id):
		return
	var coord: Vector2i = _entity_cell[id]
	if _cells.has(coord):
		_cells[coord].erase(id)
		if _cells[coord].is_empty():
			_cells.erase(coord)
	_entity_cell.erase(id)

func update(id: StringName, position: Vector2) -> void:
	var new_coord := _cell_coord(position)
	if _entity_cell.get(id) == new_coord:
		return  # still in the same cell, nothing to move
	remove(id)
	insert(id, position)

## Every entity id in the query cell plus its 8 neighbors (a 3x3 block) —
## cheap superset of "within CELL_SIZE radius," callers that need an exact
## radius filter the returned ids by actual distance themselves.
func query_nearby(position: Vector2) -> Array[StringName]:
	var center := _cell_coord(position)
	var result: Array[StringName] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var coord := center + Vector2i(dx, dy)
			if _cells.has(coord):
				for id in _cells[coord]:
					result.append(id)
	return result
