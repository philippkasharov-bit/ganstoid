## INV1: the bag as a Tarkov/DayZ grid. Every item takes cells by its size
## (a bat is 1x4, a bandage 1x1); piles of the same thing share a spot up to
## its stack limit. state.inventory stays the count every system reads and
## writes; this keeps state.bag (the layout) in step: new units go to the
## first free spot (turned if that is what fits), used ones come off the last
## pile. Space decides what you can carry; weight is shown, not enforced.
class_name BagGrid
extends RefCounted

const COLS := 8
const ROWS := 6

## Cells a pile covers, given its rotation.
static func footprint(id: StringName, rotated: bool) -> Vector2i:
	var s := ItemCatalog.size_of(id)
	return Vector2i(s.y, s.x) if rotated else s

## Cell -> index of the pile on it; `skip` leaves one pile out (the one being moved).
static func occupancy(bag: Array, skip: int = -1) -> Dictionary:
	var taken := {}
	for i in bag.size():
		if i == skip:
			continue
		var p: Dictionary = bag[i]
		var f := footprint(p["id"], p["r"])
		for dx in f.x:
			for dy in f.y:
				taken[Vector2i(p["x"] + dx, p["y"] + dy)] = i
	return taken

static func fits(taken: Dictionary, at: Vector2i, f: Vector2i, cols: int = COLS, rows: int = ROWS) -> bool:
	if at.x < 0 or at.y < 0 or at.x + f.x > cols or at.y + f.y > rows:
		return false
	for dx in f.x:
		for dy in f.y:
			if taken.has(at + Vector2i(dx, dy)):
				return false
	return true

## First free spot, reading rows left to right; tries the item upright, then turned.
static func free_spot(taken: Dictionary, id: StringName, cols: int = COLS, rows: int = ROWS) -> Dictionary:
	for rotated in [false, true]:
		var f := footprint(id, rotated)
		for y in rows:
			for x in cols:
				if fits(taken, Vector2i(x, y), f, cols, rows):
					return {"x": x, "y": y, "r": rotated}
	return {}

## How many more of `id` would fit right now (topping up piles, then new spots).
static func room_for(state: PlayerStateData, id: StringName) -> int:
	sync(state)
	var room := 0
	var stack := ItemCatalog.stack_of(id)
	for p in state.bag:
		if p["id"] == id:
			room += stack - int(p["n"])
	var trial := state.bag.duplicate(true)
	while true:
		var spot := free_spot(occupancy(trial), id)
		if spot.is_empty():
			break
		spot["id"] = id
		spot["n"] = stack
		trial.append(spot)
		room += stack
		if room > 999:
			break
	return room

## Brings the layout in line with the counts.
static func sync(state: PlayerStateData) -> void:
	var placed := {}
	for p in state.bag:
		placed[p["id"]] = placed.get(p["id"], 0) + int(p["n"])
	for id in placed:
		var extra: int = placed[id] - int(state.inventory.get(id, 0))
		if extra > 0:
			_take(state, id, extra)
	for id in state.inventory:
		var missing: int = int(state.inventory[id]) - int(placed.get(id, 0))
		if missing > 0:
			_put(state, id, missing)

static func _take(state: PlayerStateData, id: StringName, units: int) -> void:
	for i in range(state.bag.size() - 1, -1, -1):
		if units <= 0:
			return
		var p: Dictionary = state.bag[i]
		if p["id"] != id:
			continue
		var off := mini(units, int(p["n"]))
		p["n"] = int(p["n"]) - off
		units -= off
		if p["n"] <= 0:
			state.bag.remove_at(i)

## Tops up piles first; what finds no spot stays unplaced (shown as "loose").
static func _put(state: PlayerStateData, id: StringName, units: int) -> void:
	var stack := ItemCatalog.stack_of(id)
	for p in state.bag:
		if p["id"] == id and units > 0:
			var add := mini(units, stack - int(p["n"]))
			p["n"] = int(p["n"]) + add
			units -= add
	while units > 0:
		var spot := free_spot(occupancy(state.bag), id)
		if spot.is_empty():
			return
		spot["id"] = id
		spot["n"] = mini(units, stack)
		units -= int(spot["n"])
		state.bag.append(spot)

## Units counted in inventory that found no spot in the grid.
static func loose(state: PlayerStateData) -> Dictionary:
	var placed := {}
	for p in state.bag:
		placed[p["id"]] = placed.get(p["id"], 0) + int(p["n"])
	var out := {}
	for id in state.inventory:
		var left: int = int(state.inventory[id]) - int(placed.get(id, 0))
		if left > 0:
			out[id] = left
	return out

## Drag-and-drop: moves pile `index` to `at` (optionally turned). False if it does not fit.
static func move(state: PlayerStateData, index: int, at: Vector2i, rotated: bool) -> bool:
	if index < 0 or index >= state.bag.size():
		return false
	var p: Dictionary = state.bag[index]
	if not fits(occupancy(state.bag, index), at, footprint(p["id"], rotated)):
		return false
	p["x"] = at.x
	p["y"] = at.y
	p["r"] = rotated
	return true
