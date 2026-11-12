## S3a: people do not walk through each other.
##
## Every walker follows their own route and knows nothing of anyone else, so two
## people meeting on a sidewalk used to pass straight through one another. This
## nudges bodies apart after each tick's movement: any two closer than BODY_M
## each step back half the overlap, along the line between them, and the step is
## slid along walls so nobody is pushed into a building.
##
## Only near the player (the people on screen): far away nobody can see overlap,
## and the work grows with the crowd. A fine grid built each tick from just those
## people keeps it to one pass over the neighbours of each.
##
## The player is a body too: walkers step around you, you are never shoved.
class_name Crowd
extends RefCounted

const BODY_M := 0.7          # centre to centre: two shoulders passing on a sidewalk
const CELL_M := 1.5
const PUSH_SHARE := 0.5      # each of the pair takes this much of the overlap per tick
const MAX_PUSH_M := 0.08     # per tick (5 m/s): a nudge, never a teleport
const RANGE_M := 70.0        # about a screen across at street zoom
const EVERY_TICKS := 3       # 20 times a second, three ticks' worth of nudge each time
const MIN_STEP_M := 0.01     # smaller nudges are not worth a wall test
const WALL_CLEAR_M := 0.2

var overlaps_last_tick := 0  # pairs that were too close before this tick's nudge (checks)
var enabled := true          # checks compare with it off
var usec_spent := 0          # total time in separate() (checks)
var _tick := 0

## `movers`: Array[NPCData] near the player this tick. `fixed`: positions that push
## but never move (the player). `collision`: CityCollision, may be null (tests).
func separate(movers: Array, fixed: PackedVector2Array, collision: CityCollision) -> void:
	_tick += 1
	if _tick % EVERY_TICKS != 0:
		return
	var t0 := Time.get_ticks_usec()
	_separate(movers, fixed, collision)
	usec_spent += Time.get_ticks_usec() - t0

func _separate(movers: Array, fixed: PackedVector2Array, collision: CityCollision) -> void:
	overlaps_last_tick = 0
	if not enabled or movers.size() + fixed.size() < 2:
		return
	var grid := {}
	for k in movers.size():
		_put(grid, movers[k].position, k)
	for k in fixed.size():
		_put(grid, fixed[k], -1 - k)
	var push := {}   # mover index -> Vector2
	for k in movers.size():
		var p: Vector2 = movers[k].position
		var cell := Vector2i((p / CELL_M).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for other in grid.get(cell + Vector2i(dx, dy), []):
					if other == k or (other >= 0 and other < k):
						continue   # each mover pair once; fixed bodies (negative) every time
					var q: Vector2 = movers[other].position if other >= 0 else fixed[-1 - other]
					_push_pair(push, k, other, p, q)
	for k in push:
		var step: Vector2 = push[k].limit_length(MAX_PUSH_M * EVERY_TICKS)
		if step.length_squared() < MIN_STEP_M * MIN_STEP_M:
			continue
		var npc: NPCData = movers[k]
		var to := npc.position + step
		# one wall test, not a slide: a nudge that would touch a wall is simply not made
		# (the walker's own route keeps them clear of walls; the other person gives way)
		if collision == null or not collision.blocked(to, WALL_CLEAR_M):
			npc.position = to

func _push_pair(push: Dictionary, k: int, other: int, p: Vector2, q: Vector2) -> void:
	var gap := p - q
	var d := gap.length()
	if d >= BODY_M:
		return
	overlaps_last_tick += 1
	var dir := gap / d if d > 0.001 else Vector2.from_angle(float(k) * 2.399)   # same spot: any way out, stable per person
	var overlap := BODY_M - d
	if other < 0:
		push[k] = push.get(k, Vector2.ZERO) + dir * overlap            # the player does not give way
		return
	push[k] = push.get(k, Vector2.ZERO) + dir * overlap * PUSH_SHARE
	push[other] = push.get(other, Vector2.ZERO) - dir * overlap * PUSH_SHARE

static func _put(grid: Dictionary, p: Vector2, k: int) -> void:
	var cell := Vector2i((p / CELL_M).floor())
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append(k)
