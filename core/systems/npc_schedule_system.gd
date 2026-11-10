## Civilian daily routine (S1 rewrite of the Phase 1 two-state schedule).
##
## REALISM
## - Shifts on the real clock. The old rule was "work for the first 60% of the
##   day", which meant everyone left for work at midnight and came home at
##   14:24. Now each person has a shift picked by a hash of their id: most work
##   days (start 06:30-09:30, 8.5 h), some evenings (14:00-16:00, 8 h), a few
##   nights (22:00-23:30, 8 h). Dealers work the corner from mid-afternoon to
##   about 02:00. Streets fill at rush hours and empty at night by themselves.
## - People go INSIDE. Arriving at home or work used to mean wandering around
##   the doorway all day, so every door had a permanent crowd. Now a civilian
##   who arrives is indoors (off the street, not drawn) until the next shift
##   change. Dealers stay out on their corner, and about one civilian in five
##   is a loiterer who hangs around outside instead.
## - Everyone walks at their own pace (1.25-1.65 m/s by id), not one speed.
##
## - People leave early enough to arrive on time: departure = shift start minus
##   the walk (distance x DETOUR / their pace). At real walking speed on a clock
##   where a game hour is 150 real seconds, a 600 m walk is nearly three game
##   hours, so without this nobody was ever at work.
## - After any jump in time (new game, sleeping) everyone is put where their
##   routine says they are, instead of the whole city starting at home.
## - People hanging around outside stand for a while, then stroll a few metres
##   to a spot they can see. They do not route-plan to shuffle about.
##
## EFFICIENCY (this system was 80% of the sim's time)
## - Only people on the street are visited each tick. Indoors costs nothing: a
##   person is woken by a calendar (tick -> who changes plan then), and is taken
##   out of the world's "who is near" index while inside.
## - People further than NEAR_M from the player move every FAR_EVERY-th tick
##   with a matching bigger step (spread across ticks by id). Same speed over
##   the ground, a sixth of the work; nobody is close enough to see the steps.
## - Route planning is rationed (SimNav.PUBLIC_PLANS_PER_TICK): when a shift
##   ends and fifty people step out at once, they get their routes a few per
##   tick instead of all in one 100 ms frame.
##
## Takes World (weakly, to avoid a retain cycle) to reindex moved entities.
class_name NPCScheduleSystem
extends SystemBase

const ARRIVE_EPSILON := SimUnits.ARRIVE_M

## [earliest start hour, latest start hour, shift length in hours, share of civilians]
const SHIFTS := [[6.5, 9.5, 8.5, 0.78], [14.0, 16.0, 8.0, 0.14], [22.0, 23.5, 8.0, 0.08]]
const DEALER_SHIFT := [15.0, 17.0, 10.0]
const LOITER_FROM_HOUR := 7.0
const LOITER_TO_HOUR := 22.0
const LOITERER_SHARE := 0.08       # civilians who stay outside their door instead of going in
const NEVER := -1000000
const DETOUR := 1.35               # streets are longer than the straight line
const MAX_LEAD_HOURS := 3.0        # nobody sets off more than this before their shift
const PACE_MIN := 1.25             # m/s; SimUnits.WALK (1.5) is the middle of the range
const PACE_MAX := 1.65

const NEAR_M := 150.0              # full-rate movement inside this distance of the player
const FAR_EVERY := 6               # beyond it: one step per this many ticks

## Idle wander for people who stay outside (dealers, loiterers).
const IDLE_WANDER_RADIUS := 12.0   # metres: hang around the doorway / storefront
const IDLE_WALK_SPEED := SimUnits.STROLL
const IDLE_DWELL_MIN_TICKS := 300    # stand 5 s ...
const IDLE_DWELL_MAX_TICKS := 2400   # ... to 40 s between strolls
const IDLE_SPOT_TRIES := 3
const IDLE_BODY_M := 0.3

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

## Per-NPC idle-wander state (StringName -> Vector2 / StringName -> int),
## owned here and passed into WanderBehavior.advance by reference every
## tick -- see WanderBehavior's doc comment for why it doesn't hold this
## state itself. Only ever populated for NPCs currently idling at a
## destination, not every NPC every tick.
var _goal: Dictionary = {}      # npc id -> door of the building they should be at now
var _from: Dictionary = {}      # npc id -> door of the building they are coming from
var _lead: Dictionary = {}      # npc id -> ticks their walk to work takes (0 = no job)
var _due: Dictionary = {}       # tick -> Array[NPCData] whose plan changes then
var _outside: Array[NPCData] = []   # everyone on the street: the only people visited each tick
var _is_out: Dictionary = {}    # npc id -> true while in _outside
var _on_full: Dictionary = {}   # npc id -> true: public ground did not get them there, any walkable way now
var _enrolled: Dictionary = {}  # npc id -> NPCData
var _seen_entities := -1
var _last_tick := NEVER
var _idle_targets: Dictionary = {}
var _idle_dwell_until: Dictionary = {}
var stranded := 0               # perf/realism counter: people whose door no route reaches

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.NPC

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	if _last_tick > NEVER and tick != _last_tick + 1:
		_resync(entities, tick)        # time jumped (sleep): everyone is where their routine says
	elif _seen_entities != entities.size():
		_enrol(entities, tick, false)  # somebody new arrived
	_last_tick = tick
	if SimNav.active != null:
		SimNav.active.new_tick()
	var due: Variant = _due.get(tick)
	if due != null:
		_due.erase(tick)
		for npc in due:
			if not (npc.is_crew or npc.is_cop):
				_plan_day(npc, tick)
	var player_pos := _player_position()
	var i := _outside.size() - 1
	while i >= 0:
		var npc: NPCData = _outside[i]
		var leaves := npc.is_crew or npc.is_cop   # recruited: CrewSystem moves them from here on
		if not leaves and not npc.is_busy:
			leaves = _move(npc, delta, tick, player_pos)
		if leaves:
			_outside[i] = _outside[_outside.size() - 1]
			_outside.pop_back()
			_is_out.erase(npc.id)
		i -= 1

## Moves one person on the street. Returns true when they have gone indoors.
func _move(npc: NPCData, delta: float, tick: int, player_pos: Vector2) -> bool:
	var target: Variant = _goal.get(npc.id)
	if target == null:
		return true   # no home or work building: nowhere to go
	var step_delta := delta
	if npc.position.distance_squared_to(player_pos) > NEAR_M * NEAR_M:
		if (tick + _phase(npc.id)) % FAR_EVERY != 0:
			return false
		step_delta = delta * FAR_EVERY
	var before := npc.position
	var dist := npc.position.distance_to(target)
	var nav := SimNav.active
	if dist <= IDLE_WANDER_RADIUS and stays_outside(npc, tick):
		_loiter(npc, target, step_delta, tick)
	elif dist <= ARRIVE_EPSILON:
		_go_indoors(npc, target)
		return true
	elif nav != null and nav.finished(npc.id, target):
		# The route ran out short of the door.
		if dist <= SimNav.LAST_HOP_M or _on_full.has(npc.id):
			if dist > SimNav.LAST_HOP_M:
				stranded += 1
			_go_indoors(npc, npc.position)   # in by whatever entrance they reached: no snap across the lot
			return true
		_on_full[npc.id] = true   # public ground does not reach it: take any walkable way
		nav.forget(npc.id)
	else:
		var layer := "full" if _on_full.has(npc.id) else _layer(npc)
		npc.position = WanderBehavior.step_toward(npc.position, target, pace(npc.id), step_delta, ARRIVE_EPSILON, npc.id, layer)
	if npc.position != before:
		_world.reindex_position(npc.id)
	return false

func _go_indoors(npc: NPCData, door: Vector2) -> void:
	npc.indoors = true
	npc.position = door
	_world.spatial_index.remove(npc.id)   # nobody on the street can see, rob or talk to them
	_on_full.erase(npc.id)
	WanderBehavior.clear(npc.id, _idle_targets, _idle_dwell_until)
	if SimNav.active != null:
		SimNav.active.forget(npc.id)

func _step_out(npc: NPCData) -> void:
	npc.indoors = false
	_world.reindex_position(npc.id)
	if not _is_out.has(npc.id):
		_is_out[npc.id] = true
		_outside.append(npc)

## Hanging around a doorway: stand, then stroll to a nearby spot in plain sight.
func _loiter(npc: NPCData, anchor: Vector2, delta: float, tick: int) -> void:
	if tick < _idle_dwell_until.get(npc.id, 0):
		return
	var spot: Variant = _idle_targets.get(npc.id)
	if spot == null or npc.position.distance_to(spot) <= ARRIVE_EPSILON:
		_idle_dwell_until[npc.id] = tick + randi_range(IDLE_DWELL_MIN_TICKS, IDLE_DWELL_MAX_TICKS)
		_idle_targets.erase(npc.id)
		for k in IDLE_SPOT_TRIES:
			var pick := anchor + Vector2.from_angle(randf() * TAU) * randf_range(1.0, IDLE_WANDER_RADIUS)
			if SimNav.active != null:
				pick = SimNav.active.snap(pick, _layer(npc))
				if not SimNav.active.collision.line_clear(npc.position, pick, IDLE_BODY_M):
					continue
			_idle_targets[npc.id] = pick
			break
		return
	npc.position = npc.position.move_toward(spot, IDLE_WALK_SPEED * delta)

## Everyone this system runs, found once; `settle` also puts them where their
## routine says they are right now.
func _enrol(entities: Dictionary, tick: int, settle: bool) -> void:
	_seen_entities = entities.size()
	for entity in entities.values():
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc.is_cop or npc.is_crew or entity.has_component(ComponentNames.PLAYER_STATE):
			continue
		if _enrolled.has(npc.id) and not settle:
			continue
		_enrolled[npc.id] = npc
		_lead[npc.id] = _walk_ticks(npc)
		_plan_day(npc, tick)
		if settle:
			_settle(npc, tick)

## New game: put everyone where their routine says they are at `tick` (at work,
## at home, on their corner) instead of all starting at home. Call once after
## the world is generated; a later jump in time does this by itself.
func settle_all(tick: int) -> void:
	_resync(_world.get_entities_with_component(ComponentNames.NPC), tick)
	_last_tick = tick

func _resync(entities: Dictionary, tick: int) -> void:
	_due.clear()
	_outside.clear()
	_is_out.clear()
	_goal.clear()
	_from.clear()
	_on_full.clear()
	_enrol(entities, tick, true)

## Puts one person where they would be by now: inside (or outside the door, for
## those who hang around), unless they should only just have set off.
func _settle(npc: NPCData, tick: int) -> void:
	var target: Variant = _goal.get(npc.id)
	if target == null:
		return
	if _just_left(npc, tick):
		npc.position = _from.get(npc.id, target)
		_step_out(npc)
	elif stays_outside(npc, tick):
		npc.position = target
		_step_out(npc)
	else:
		_go_indoors(npc, target)
		_is_out.erase(npc.id)
		_outside.erase(npc)

## Works out where this person should be now and when that next changes; called
## when it changes, not per tick. Leaving for somewhere new puts them on the street.
func _plan_day(npc: NPCData, tick: int) -> void:
	var window := _work_window(npc, tick)   # x: ticks into it (or past it), y: its length, both from departure
	var heading_to_work := _has_building(npc.work_building_id) and window.x < window.y
	var target_id: StringName = npc.work_building_id if heading_to_work else npc.home_building_id
	var from_id: StringName = npc.home_building_id if heading_to_work else npc.work_building_id
	var change := maxi(1, (window.y if heading_to_work else SimClock.day_ticks) - window.x)
	var wake := tick + mini(change, _ticks_to_loiter_edge(npc, tick))
	if not _due.has(wake):
		_due[wake] = []
	_due[wake].append(npc)
	if not _has_building(target_id):
		_goal.erase(npc.id)
		return
	var door: Vector2 = _world.entities[target_id].get_component(ComponentNames.BUILDING).position
	if _has_building(from_id):
		_from[npc.id] = _world.entities[from_id].get_component(ComponentNames.BUILDING).position
	var had: Variant = _goal.get(npc.id)
	_goal[npc.id] = door
	if had == null or had != door:
		WanderBehavior.clear(npc.id, _idle_targets, _idle_dwell_until)
		_step_out(npc)
	elif npc.indoors and stays_outside(npc, tick):
		_step_out(npc)   # morning: the ones who hang around come back out

func _has_building(id: StringName) -> bool:
	return id != &"" and _world.entities.has(id)

## Ticks this person's walk between home and work takes at their pace.
func _walk_ticks(npc: NPCData) -> int:
	if not (_has_building(npc.home_building_id) and _has_building(npc.work_building_id)):
		return 0
	var home: Vector2 = _world.entities[npc.home_building_id].get_component(ComponentNames.BUILDING).position
	var work: Vector2 = _world.entities[npc.work_building_id].get_component(ComponentNames.BUILDING).position
	var seconds := home.distance_to(work) * DETOUR / pace(npc.id)
	return mini(int(seconds * SimClock.TICKS_PER_SECOND), SimClock.hours(MAX_LEAD_HOURS))

## The stretch of the day this person is at work or walking there: it opens when
## they must leave home to be on time and closes at the end of the shift.
## Returns (ticks since it opened, its length in ticks).
func _work_window(npc: NPCData, tick: int) -> Vector2i:
	var shift := shift_of(npc)
	var day := SimClock.day_ticks
	var lead: int = _lead.get(npc.id, 0)
	var opened := int(shift.x * day) - lead
	return Vector2i(posmod(posmod(tick, day) - opened, day), int(shift.y * day) + lead)

## True while they would still be in the first half of a walk that began at the
## last plan change (used when settling people after a jump in time).
func _just_left(npc: NPCData, tick: int) -> bool:
	var lead: int = _lead.get(npc.id, 0)
	if lead <= 0:
		return false
	var window := _work_window(npc, tick)
	var since_change := window.x if window.x < window.y else window.x - window.y
	return since_change < lead / 2

## Ticks until the hour people who hang around outside come out or go in.
func _ticks_to_loiter_edge(npc: NPCData, tick: int) -> int:
	if npc.is_dealer or _unit(npc.id, 3) >= LOITERER_SHARE:
		return SimClock.day_ticks
	var now := SimClock.day_fraction(tick)
	var best := 1.0
	for hour in [LOITER_FROM_HOUR, LOITER_TO_HOUR]:
		var gap := fposmod(hour / 24.0 - now, 1.0)
		if gap > 0.0:
			best = minf(best, gap)
	return maxi(1, int(ceil(best * SimClock.day_ticks)))

func _player_position() -> Vector2:
	for entity in _world.get_entities_with_component(ComponentNames.PLAYER_STATE).values():
		return entity.get_component(ComponentNames.NPC).position
	return Vector2.INF   # no player (some checks): everyone is "far"

## [start, length] of this person's shift as fractions of a day.
static func shift_of(npc: NPCData) -> Vector2:
	var roll := _unit(npc.id, 1)
	var row: Array = DEALER_SHIFT
	if not npc.is_dealer:
		var acc := 0.0
		for candidate in SHIFTS:
			row = candidate
			acc += candidate[3]
			if roll < acc:
				break
	var start: float = lerpf(row[0], row[1], _unit(npc.id, 2))
	return Vector2(start / 24.0, row[2] / 24.0)

static func is_work_time(npc: NPCData, tick: int) -> bool:
	var shift := shift_of(npc)
	return fposmod(SimClock.day_fraction(tick) - shift.x, 1.0) < shift.y

## Ticks from `tick` to this person's next shift start or end (at least 1).
static func ticks_until_flip(npc: NPCData, tick: int) -> int:
	var shift := shift_of(npc)
	var into := fposmod(SimClock.day_fraction(tick) - shift.x, 1.0)
	var left := shift.y - into if into < shift.y else 1.0 - into
	return maxi(1, int(ceil(left * SimClock.day_ticks)))

## Kept for callers that print it: this person's shift start, in ticks after midnight.
static func schedule_offset(npc_id: StringName) -> int:
	var npc := NPCData.new()
	npc.id = npc_id
	return int(shift_of(npc).x * SimClock.day_ticks)

## Who is out on the street instead of indoors once they have arrived: dealers
## while they are working their corner, and loiterers during the day. At night,
## and dealers off shift, go inside like everyone else.
static func stays_outside(npc: NPCData, tick: int) -> bool:
	if npc.is_dealer:
		return is_work_time(npc, tick)
	var hour := SimClock.day_fraction(tick) * 24.0
	return _unit(npc.id, 3) < LOITERER_SHARE and hour >= LOITER_FROM_HOUR and hour < LOITER_TO_HOUR

static func pace(npc_id: StringName) -> float:
	return lerpf(PACE_MIN, PACE_MAX, _unit(npc_id, 4))

static func _phase(npc_id: StringName) -> int:
	return absi(hash(npc_id)) % FAR_EVERY

## Stable 0..1 number from an id; `salt` gives independent rolls for one person.
static func _unit(npc_id: StringName, salt: int) -> float:
	return float(absi(hash([npc_id, salt])) % 10007) / 10007.0

## Civilians keep to public ground; dealers know the shortcuts.
static func _layer(npc: NPCData) -> String:
	return "full" if npc.is_dealer else "public"
