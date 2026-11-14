## Everyone out on the street, and how they move (S1/S2, split out of
## NPCScheduleSystem in S3c). The system decides WHERE a person should go
## (start_trip); this walks them there, leg by leg, and tells the system when
## they have gone in somewhere (on_arrived).
##
## A trip is a list of legs {p, stay}: stay 0 = walk past, > 0 = go inside for
## that many ticks, FINAL = the end of the trip (home or work).
##
## EFFICIENCY
## - Only people on the street are in `outside` and visited each tick; going in
##   takes a person out of the world's "who is near" index too.
## - People further than NEAR_M from the player move every FAR_EVERY-th tick with
##   a matching bigger step: same speed over the ground, a sixth of the work.
## - People hanging around a doorway stroll to a spot in sight; no route planning.
class_name NPCStreet
extends RefCounted

const FINAL := -1
const ARRIVE_EPSILON := SimUnits.ARRIVE_M
const PASS_M := 4.0                # close enough to a point one only walks past
const NEAR_M := 150.0              # full-rate movement inside this distance of the player
const FAR_EVERY := 6               # beyond it: one step per this many ticks
const ABSTRACT_M := 520.0          # POP1: past the streamed city (CityStream3D.UNLOAD_M + margin) walkers go straight, no routes
const PAUSE_EVERY_S := 40.0        # near the player, a walker stops about this often ...
const PAUSE_TICKS := [90, 360]     # ... for 1.5 to 6 s (phone, shoelace, looking around)
## Hanging around outside (dealers, loiterers).
const IDLE_WANDER_RADIUS := 12.0   # metres: the doorway / storefront
const IDLE_WALK_SPEED := SimUnits.STROLL
const IDLE_DWELL_MIN_TICKS := 300    # stand 5 s ...
const IDLE_DWELL_MAX_TICKS := 2400   # ... to 40 s between strolls
const IDLE_SPOT_TRIES := 3
const IDLE_PICKS_PER_TICK := 3     # PF3: new loiter spots chosen per tick (each costs up to three navmesh snaps)
var _picks_left := IDLE_PICKS_PER_TICK
const IDLE_BODY_M := 0.3

var outside: Array[NPCData] = []   # everyone on the street
var pace_now: Dictionary = {}      # npc id -> m/s for this trip (a stroll is slower)
var crowd := Crowd.new()           # S3a: bodies do not overlap near the player
var stranded := 0                  # people whose door no route reaches (checks)
## Called as on_arrived.call(npc, tick, visit_ticks) when someone goes in:
## visit_ticks > 0 for a visit on the way, 0 when the trip is over.
var on_arrived: Callable

var _world_ref: WeakRef
var _is_out: Dictionary = {}       # npc id -> true while in `outside`
var _goal: Dictionary = {}         # npc id -> the point they are walking to right now
var _stay: Dictionary = {}         # npc id -> the stay at _goal
var _legs: Dictionary = {}         # npc id -> the legs after _goal
var _final: Dictionary = {}        # npc id -> the door the whole trip ends at
var _on_full: Dictionary = {}      # npc id -> public ground did not get them there: any walkable way
var _pause_until: Dictionary = {}
var _idle_targets: Dictionary = {}
var _idle_dwell_until: Dictionary = {}

func _init(world: World) -> void:
	_world_ref = weakref(world)

func _world() -> World:
	return _world_ref.get_ref()

func final_of(npc_id: StringName) -> Variant:
	return _final.get(npc_id)

func clear() -> void:
	outside.clear()
	for book in [_is_out, _goal, _stay, _legs, _final, _on_full, pace_now, _pause_until]:
		book.clear()

## Moves everyone outside one tick; people near the player then step apart.
func step_all(delta: float, tick: int, player_pos: Vector2) -> void:
	var near: Array[NPCData] = []
	_picks_left = IDLE_PICKS_PER_TICK
	var i := outside.size() - 1
	while i >= 0:
		var npc: NPCData = outside[i]
		var leaves := npc.is_crew or npc.is_cop or npc.is_down   # recruited: CrewSystem moves them; down: they lie where they fell
		if not leaves and not npc.is_busy:
			leaves = _move(npc, delta, tick, player_pos)
			if not leaves and npc.position.distance_squared_to(player_pos) < Crowd.RANGE_M * Crowd.RANGE_M:
				near.append(npc)
		if leaves:
			outside[i] = outside[outside.size() - 1]
			outside.pop_back()
			_is_out.erase(npc.id)
		i -= 1
	if near.is_empty():
		return
	var fixed := PackedVector2Array() if player_pos == Vector2.INF else PackedVector2Array([player_pos])
	crowd.separate(near, fixed, SimNav.active.collision if SimNav.active != null else null)
	for npc in near:
		_world().reindex_position(npc.id)

## Sets someone off: through `stops` ({p, stay}) and on to the door `final`.
func start_trip(npc: NPCData, stops: Array, final: Vector2, trip_pace: float) -> void:
	var legs := stops.duplicate()
	legs.append({"p": final, "stay": FINAL})
	_legs[npc.id] = legs
	_final[npc.id] = final
	if trip_pace > 0.0:
		pace_now[npc.id] = trip_pace
	else:
		pace_now.erase(npc.id)
	WanderBehavior.clear(npc.id, _idle_targets, _idle_dwell_until)
	next_leg(npc)
	step_out(npc)

## Puts someone at the end of their trip already (time jumped).
func place_at_end(npc: NPCData, door: Vector2) -> void:
	_final[npc.id] = door
	_legs[npc.id] = []
	_goal[npc.id] = door
	_stay[npc.id] = FINAL

func forget_trip(npc_id: StringName) -> void:
	_goal.erase(npc_id)

func next_leg(npc: NPCData) -> void:
	var leg: Dictionary = _legs[npc.id].pop_front()
	_goal[npc.id] = leg["p"]
	_stay[npc.id] = leg["stay"]
	_on_full.erase(npc.id)
	if SimNav.active != null:
		SimNav.active.forget(npc.id)

func go_indoors(npc: NPCData, door: Vector2) -> void:
	npc.indoors = true
	npc.position = door
	_world().spatial_index.remove(npc.id)   # nobody on the street can see, rob or talk to them
	_on_full.erase(npc.id)
	WanderBehavior.clear(npc.id, _idle_targets, _idle_dwell_until)
	if SimNav.active != null:
		SimNav.active.forget(npc.id)

## Indoors and off the street list at once (settling after a jump in time). Not
## for use inside step_all: that loop takes people off the list itself.
func put_inside(npc: NPCData, door: Vector2) -> void:
	go_indoors(npc, door)
	if _is_out.has(npc.id):
		_is_out.erase(npc.id)
		outside.erase(npc)

func step_out(npc: NPCData) -> void:
	npc.indoors = false
	_world().reindex_position(npc.id)
	if not _is_out.has(npc.id):
		_is_out[npc.id] = true
		outside.append(npc)

## Moves one person on the street. Returns true when they have gone indoors.
func _move(npc: NPCData, delta: float, tick: int, player_pos: Vector2) -> bool:
	var target: Variant = _goal.get(npc.id)
	if target == null:
		return true   # no home or work building: nowhere to go
	var step_delta := delta
	var player_d2 := npc.position.distance_squared_to(player_pos)
	var unseen := player_d2 > ABSTRACT_M * ABSTRACT_M   # POP1: past the built city: nobody can see the route
	if player_d2 > NEAR_M * NEAR_M:
		if (tick + _phase(npc.id)) % FAR_EVERY != 0:
			return false
		step_delta = delta * FAR_EVERY
	elif _pausing(npc, tick):
		return false
	var before := npc.position
	var dist := npc.position.distance_to(target)
	var stay: int = _stay.get(npc.id, FINAL)
	var nav := SimNav.active
	if stay == FINAL and dist <= IDLE_WANDER_RADIUS and NPCRoutine.stays_outside(npc, tick):
		if not unseen:
			_loiter(npc, target, step_delta, tick)   # POP1: out of sight they just stand at the door
	elif unseen:
		npc.position = WanderBehavior.step_toward(npc.position, target, pace_now.get(npc.id, NPCRoutine.pace(npc.id)), step_delta, PASS_M if stay == 0 else ARRIVE_EPSILON)   # POP1: a straight line, no navmesh
		if nav != null:
			nav.forget(npc.id)
	elif dist <= ARRIVE_EPSILON or (stay == 0 and dist <= PASS_M):
		return _arrive(npc, target, tick)
	elif nav != null and nav.finished(npc.id, target):
		# The route ran out short of the point.
		if stay == 0 or dist <= SimNav.LAST_HOP_M or _on_full.has(npc.id):
			if stay != 0 and dist > SimNav.LAST_HOP_M:
				stranded += 1
			return _arrive(npc, npc.position, tick)   # in by whatever entrance they reached: no snap across the lot
		_on_full[npc.id] = true   # public ground does not reach it: take any walkable way
		nav.forget(npc.id)
	else:
		var layer := "full" if _on_full.has(npc.id) else NPCRoutine.layer_at(npc, tick)
		npc.position = WanderBehavior.step_toward(npc.position, target, pace_now.get(npc.id, NPCRoutine.pace(npc.id)), step_delta, ARRIVE_EPSILON, npc.id, layer)
	if npc.position != before:
		_world().reindex_position(npc.id)
	return false

## Reached the current point: walk on, go in for a while, or the trip is over.
func _arrive(npc: NPCData, at: Vector2, tick: int) -> bool:
	var stay: int = _stay.get(npc.id, FINAL)
	if stay == 0 and not _legs.get(npc.id, []).is_empty():
		next_leg(npc)
		return false
	go_indoors(npc, at)
	if stay <= 0:
		pace_now.erase(npc.id)
	if on_arrived.is_valid():
		on_arrived.call(npc, tick, maxi(stay, 0))
	return true

func _pausing(npc: NPCData, tick: int) -> bool:
	if tick < _pause_until.get(npc.id, 0):
		return true
	if randf() * PAUSE_EVERY_S * SimClock.TICKS_PER_SECOND < 1.0:
		_pause_until[npc.id] = tick + randi_range(PAUSE_TICKS[0], PAUSE_TICKS[1])
		return true
	return false

## Hanging around a doorway: stand, then stroll to a nearby spot in plain sight.
func _loiter(npc: NPCData, anchor: Vector2, delta: float, tick: int) -> void:
	if tick < _idle_dwell_until.get(npc.id, 0):
		return
	var spot: Variant = _idle_targets.get(npc.id)
	if spot == null or npc.position.distance_to(spot) <= ARRIVE_EPSILON:
		if _picks_left <= 0:
			return   # PF3: a navmesh snap is ~0.4 ms; the rest pick their spot next tick
		_picks_left -= 1
		_idle_dwell_until[npc.id] = tick + randi_range(IDLE_DWELL_MIN_TICKS, IDLE_DWELL_MAX_TICKS)
		_idle_targets.erase(npc.id)
		for k in IDLE_SPOT_TRIES:
			var pick := anchor + Vector2.from_angle(randf() * TAU) * randf_range(1.0, IDLE_WANDER_RADIUS)
			if SimNav.active != null:
				pick = SimNav.active.snap(pick, NPCRoutine.home_layer(npc))
				if not SimNav.active.collision.line_clear(npc.position, pick, IDLE_BODY_M):
					continue
			_idle_targets[npc.id] = pick
			break
		return
	npc.position = npc.position.move_toward(spot, IDLE_WALK_SPEED * delta)

static func _phase(npc_id: StringName) -> int:
	return absi(hash(npc_id)) % FAR_EVERY
