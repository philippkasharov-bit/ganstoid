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

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i((p / CELL_M).floor())

static func centre_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL_M
