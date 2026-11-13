## Turf (TR1): the district cut into CELL_M squares; each holds every gang's
## influence there (0-100). The player's own outfit is the gang id &"player".
## One entity carries it, so a save keeps the map of who holds what.
class_name TerritoryData
extends Resource

const CELL_M := 120.0

@export var cells: Dictionary = {}          # Vector2i -> {gang id: influence}
@export var last_hour: int = -1
@export var war_until: Dictionary = {}       # gang id -> tick their last hit squad stands down
@export var taxed_day: int = -1

## T1: turf is held per street block (Hoods); off the map's blocks, per CELL_M square.
static func cell_of(p: Vector2) -> Vector2i:
	var h := Hoods.data()
	if h != null:
		var k := h.key_of(p)
		if k.x >= 0:
			return k
	return Vector2i((p / CELL_M).floor())

## T2: turf is held per street (capture point); off the map's streets, per grid square.
static func turf_of(p: Vector2) -> Vector2i:
	var h := Hoods.data()
	if h != null and not h.streets.is_empty():
		var k := h.street_of(p)
		if k.x >= 0:
			return k
	return cell_of(p)

static func centre_of(c: Vector2i) -> Vector2:
	if (Hoods.is_block(c) or Hoods.is_street(c)) and Hoods.data() != null:
		return Hoods.data().place(c).get("c", Vector2.ZERO)
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL_M

## The places next to `c`: the blocks across its streets, or the four grid squares round it.
static func neighbours(c: Vector2i) -> Array[Vector2i]:
	if (Hoods.is_block(c) or Hoods.is_street(c)) and Hoods.data() != null:
		return Hoods.data().neighbours(c)
	var out: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		out.append(c + d)
	return out
