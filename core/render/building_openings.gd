## DW1: doors and windows on the walls you can see (2.5D). Windows run in rows,
## one per storey, every few metres along the wall: glass by day, some lit
## warm at night. The ground floor of the door wall gets the door (a dark
## frame with a lighter step) instead of the windows next to it. Drawn as
## plain quads into the cached building layer, close zoom only.
class_name BuildingOpenings
extends RefCounted

const SPACING_M := 3.6
const WIDTH_M := 1.3
const DOOR_M := 1.6
const MAX_ROWS := 10        # tall towers: rows get spread over the wall instead of hundreds of them
const GLASS_DAY := Color(0.36, 0.45, 0.52)
const GLASS_NIGHT := Color(0.13, 0.15, 0.19)
const LIT := Color(0.98, 0.84, 0.48)
const FRAME := Color(0.18, 0.15, 0.13)
const DOOR := Color(0.24, 0.17, 0.12)

## Wall a->c lifted by `lift`; door_t (0..1, or -1) puts a door on the ground floor.
static func draw_wall(ci: CanvasItem, a: Vector2, c: Vector2, lift: Vector2, levels: int, door_t: float, night: bool, seed: int) -> void:
	var length := a.distance_to(c)
	if length < SPACING_M:
		return
	var along := (c - a) / length
	if absf(along.x) < 0.35:
		return   # a wall seen nearly edge-on: windows would be slivers (and fail to draw)
	var rows := clampi(levels, 1, MAX_ROWS)
	var row_h := lift / rows
	var count := int(length / SPACING_M)
	var start := (length - (count - 1) * SPACING_M) * 0.5
	var door_m := door_t * length
	for r in rows:
		for k in count:
			var m := start + k * SPACING_M
			if r == 0 and door_t >= 0.0 and absf(m - door_m) < DOOR_M + WIDTH_M:
				continue   # the door takes this spot
			_window(ci, a + along * m, along, row_h, r, night and _lit(seed, r, k), night)
	if door_t >= 0.0:
		_door(ci, a + along * door_m, along, row_h)

static func _lit(seed: int, r: int, k: int) -> bool:
	return absi((seed * 31 + r * 17 + k * 7) % 10) < 4   # about 4 in 10 windows lit at night

static func _window(ci: CanvasItem, at: Vector2, along: Vector2, row_h: Vector2, r: int, lit: bool, night_glass: bool) -> void:
	var half := along * WIDTH_M * 0.5
	var low := at + row_h * (r + 0.28)
	var high := at + row_h * (r + 0.78)
	var glass := LIT if lit else (GLASS_NIGHT if night_glass else GLASS_DAY)
	_quad(ci, low - half, low + half, high + half, high - half, FRAME)
	var inset := along * 0.12
	_quad(ci, low - half + inset, low + half - inset, high + half - inset, high - half + inset, glass)

static func _door(ci: CanvasItem, at: Vector2, along: Vector2, row_h: Vector2) -> void:
	var half := along * DOOR_M * 0.5
	var top := at + row_h * 0.85
	_quad(ci, at - half, at + half, top + half, top - half, DOOR)
	_quad(ci, at - half * 1.2, at + half * 1.2, at + half * 1.2 + row_h * 0.08, at - half * 1.2 + row_h * 0.08, Color(0.6, 0.58, 0.55))   # the step

static func _quad(ci: CanvasItem, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color) -> void:
	ci.draw_primitive(PackedVector2Array([p0, p1, p2, p3]), PackedColorArray([col, col, col, col]), PackedVector2Array())
