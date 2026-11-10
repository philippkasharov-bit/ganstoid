## S3b: a cop on foot walks a beat, not a random spot in a circle.
##
## Before, a patrolling cop picked any point within 150 m of the station and
## walked to it in a straight-ish line, often across yards, then picked another.
## A real foot patrol walks the streets around the station in a loop and stops
## at the corners. So each cop gets a beat: BEAT_STOPS corners spread round the
## station, each snapped to the nearest sidewalk, walked in order along the
## sidewalks, with a look around at each.
##
## Beats differ by cop and by day: each cop's loop has its own size, starting
## corner and direction, and they change from one day to the next, so the
## player cannot learn one fixed timetable (but can learn a cop's area).
##
## A beat is worked out the first time a cop needs one each day (a few snaps,
## about 1 ms each), so nothing is spent on cops nobody is near.
class_name CopBeat
extends RefCounted

const BEAT_STOPS := 6
const RADIUS_M := [55.0, 110.0]       # how far from the station the loop runs (stays inside the 150 m leash)
const STOP_TICKS := [300, 1200]       # 5-20 s looking around at each corner
const LAYER := "public"               # sidewalks and crosswalks, like the public
const MAX_DETOUR := 1.8               # a leg may be this much longer than the straight line

var _beats := {}      # cop id -> {day, stops: Array[Vector2], next: int, wait_until: int}
var corners_reached := 0   # checks
var _planned_at := -1

## Where the cop moves this tick. `station` is the beat's centre.
func advance(npc: NPCData, station: Vector2, speed: float, delta: float, tick: int) -> Vector2:
	var day := floori(float(tick) / SimClock.day_ticks)
	var beat: Dictionary = _beats.get(npc.id, {})
	if beat.is_empty() or beat["day"] != day or beat["station"] != station:
		if _planned_at == tick:   # one beat worked out per tick: at midnight all cops would want one at once
			return npc.position
		_planned_at = tick
		beat = _plan(npc, station, day)
		_beats[npc.id] = beat
	if tick < beat["wait_until"]:
		return npc.position
	var stop: Vector2 = beat["stops"][beat["next"]]
	if npc.position.distance_to(stop) <= SimUnits.ARRIVE_M * 2.0:
		beat["next"] = (beat["next"] + 1) % beat["stops"].size()
		corners_reached += 1
		beat["wait_until"] = tick + randi_range(STOP_TICKS[0], STOP_TICKS[1])
		if SimNav.active != null:
			SimNav.active.forget(npc.id)
		return npc.position
	return WanderBehavior.step_toward(npc.position, stop, speed, delta, SimUnits.ARRIVE_M, npc.id, LAYER)

## Drops a cop's beat (called when they go off on a call: back on patrol they
## pick the loop up from the nearest corner).
func forget(npc_id: StringName) -> void:
	_beats.erase(npc_id)

func stops_of(npc_id: StringName) -> Array:
	return _beats.get(npc_id, {}).get("stops", [])

func _plan(npc: NPCData, station: Vector2, day: int) -> Dictionary:
	var npc_id := npc.id
	var size := lerpf(RADIUS_M[0], RADIUS_M[1], _roll(npc_id, day, 1))
	var turn := 1.0 if _roll(npc_id, day, 2) < 0.5 else -1.0
	var start := _roll(npc_id, day, 3) * TAU
	var stops: Array[Vector2] = []
	for k in BEAT_STOPS:
		var at := station + Vector2.from_angle(start + turn * TAU * k / BEAT_STOPS) * size * lerpf(0.75, 1.2, _roll(npc_id, day, 10 + k))
		if SimNav.active == null:
			stops.append(at)
			continue
		at = SimNav.active.snap(at, LAYER)
		# a corner the sidewalks only reach the long way round (across a freeway, round a
		# superblock) is not on a foot beat: skip it
		if stops.is_empty() or _walk_m(stops[stops.size() - 1], at) <= stops[stops.size() - 1].distance_to(at) * MAX_DETOUR + 30.0:
			stops.append(at)
	if stops.size() < 2:
		stops = [station, station]
	var nearest := 0
	for k in stops.size():
		if stops[k].distance_squared_to(npc.position) < stops[nearest].distance_squared_to(npc.position):
			nearest = k
	return {"day": day, "station": station, "stops": stops, "next": nearest, "wait_until": 0}

static func _walk_m(a: Vector2, b: Vector2) -> float:
	var path: PackedVector2Array = SimNav.active.navs[LAYER].path(a, b)
	if path.size() < 2 or path[path.size() - 1].distance_to(b) > 3.0:
		return INF
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	return total

static func _roll(npc_id: StringName, day: int, salt: int) -> float:
	return float(absi(hash([npc_id, day, salt])) % 10007) / 10007.0
