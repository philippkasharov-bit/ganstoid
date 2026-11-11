## Civilian daily life: decides where each person should be and when that next
## changes. Split in S3c into three parts:
##   NPCRoutine          the rules (shifts, loiterers, pace, dark routes): pure functions
##   NPCScheduleSystem   this: the calendar and the day's decisions
##   NPCStreet           everyone outside and how they walk there
##
## REALISM
## - People leave early enough to arrive on time: departure = shift start minus
##   the walk (distance x DETOUR / their pace).
## - In free time people run errands, go out in the evening or take a stroll
##   (NPCOutings), and take a different way to work on different days.
## - After any jump in time (new game, sleeping) everyone is put where their
##   routine says they are, instead of the whole city starting at home.
##
## EFFICIENCY (this was 80% of the sim's time before S1)
## - Nobody is looked at per tick here: a calendar (tick -> who) wakes a person
##   only when their plan changes, at most WAKES_PER_TICK in one tick.
##
## Takes World weakly (no retain cycle).
class_name NPCScheduleSystem
extends SystemBase

const NEVER := -1000000
const WAKES_PER_TICK := 6          # people re-planning their day in one tick
const OUTING_SLACK := 1.3          # only go out with this much more free time than the outing needs

var street: NPCStreet
var outings_started := 0           # realism counter (verify_sim_life)
var fled := 0                      # people sent running by gunfire (verify_combat)

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _outings := NPCOutings.new()
var _homebound: Dictionary = {}    # npc id -> their trip ends at home (free time)
var _visit_until: Dictionary = {}  # npc id -> tick their stay inside a business ends
var _outing_at: Dictionary = {}    # npc id -> tick they next think about going out
var _routine_wake: Dictionary = {} # npc id -> tick their queued routine wake-up is at
var _from: Dictionary = {}         # npc id -> door of the building they are coming from
var _lead: Dictionary = {}         # npc id -> ticks their walk to work takes (0 = no job)
var _due: Dictionary = {}          # tick -> Array[NPCData] whose plan changes then
var _enrolled: Dictionary = {}     # npc id -> NPCData
var _seen_entities := -1
var _last_tick := NEVER

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.NPC
	street = NPCStreet.new(world)
	street.on_arrived = _on_arrived

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	if _last_tick > NEVER and tick != _last_tick + 1:
		_resync(entities, tick)        # time jumped (sleep): everyone is where their routine says
	elif _seen_entities != entities.size():
		_enrol(entities, tick, false)  # somebody new arrived
	_last_tick = tick
	if SimNav.active != null:
		SimNav.active.new_tick(tick)
	var due: Variant = _due.get(tick)
	if due != null:
		_due.erase(tick)
		if due.size() > WAKES_PER_TICK:   # a crowd on one tick (a shift ending) is spread over the next few
			if not _due.has(tick + 1):
				_due[tick + 1] = []
			_due[tick + 1].append_array(due.slice(WAKES_PER_TICK))
			due = due.slice(0, WAKES_PER_TICK)
		for npc in due:
			if not (npc.is_crew or npc.is_cop or npc.is_down):
				_plan_day(npc, tick)
	street.step_all(delta, tick, _player_position())

## New game: put everyone where their routine says they are at `tick` (at work,
## at home, on their corner) instead of all starting at home. Call once after
## the world is generated; a later jump in time does this by itself.
func settle_all(tick: int) -> void:
	_resync(_world.get_entities_with_component(ComponentNames.NPC), tick)
	_last_tick = tick

## Combat C5: a shot. Everyone outside within earshot (dealers excepted: they
## have heard it before) runs for home at a jog; the calendar takes over again
## once they are in.
func on_gunshot(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.GUNSHOT:
		return
	var at: Vector2 = payload["position"]
	var reach_sq: float = payload["heard_m"] * payload["heard_m"]
	for npc in street.outside.duplicate():
		if not npc.is_dealer and npc.position.distance_squared_to(at) <= reach_sq:
			flee(npc)

## Runs home at a jog (gunfire, or W2: they saw something and want a phone).
func flee(npc: NPCData) -> void:
	if npc.is_down or npc.is_crew or npc.is_cop or npc.indoors or not _has_building(npc.home_building_id):
		return
	_homebound[npc.id] = true
	_visit_until.erase(npc.id)
	street.start_trip(npc, [], _door(npc.home_building_id), SimUnits.JOG)
	fled += 1

## G3: someone back on their feet (a knockout ended): pick their day up again.
func replan(npc: NPCData, tick: int) -> void:
	street.forget_trip(npc.id)
	_routine_wake.erase(npc.id)
	_plan_day(npc, tick)

## How many people are inside a business on an errand or evening out right now (checks).
func visiting_count() -> int:
	return _visit_until.size()

## NPCStreet: someone went in. A visit on the way: wake them when it is over.
## The end of the trip: if that is home, they will think about going out later.
func _on_arrived(npc: NPCData, tick: int, visit_ticks: int) -> void:
	if visit_ticks > 0:
		_visit_until[npc.id] = tick + visit_ticks
		_wake(npc, tick + visit_ticks)
	elif _homebound.has(npc.id):
		_think_about_going_out(npc, tick)

func _wake(npc: NPCData, at: int) -> void:
	if not _due.has(at):
		_due[at] = []
	_due[at].append(npc)

func _think_about_going_out(npc: NPCData, tick: int) -> void:
	if npc.is_dealer:
		return
	_outing_at[npc.id] = tick + NPCOutings.next_gap(npc.id, _world.runtime_rng)
	_wake(npc, _outing_at[npc.id])

## Free and at home, and the moment has come: an errand, an evening out or a
## stroll, if there is time for it before work. Otherwise think again later.
func _maybe_go_out(npc: NPCData, home: Vector2, tick: int, free_ticks: int) -> void:
	_outing_at.erase(npc.id)
	var outing := _outings.plan(_world, npc, home, SimClock.day_fraction(tick) * 24.0, _world.runtime_rng)
	if outing.is_empty() or _outing_ticks(npc, outing, home) * OUTING_SLACK > free_ticks:
		_think_about_going_out(npc, tick)
		return
	street.start_trip(npc, outing["legs"], home, outing["pace"])
	outings_started += 1

func _outing_ticks(npc: NPCData, outing: Dictionary, home: Vector2) -> int:
	var metres := 0.0
	var inside := 0
	var at := home
	for leg in outing["legs"]:
		metres += at.distance_to(leg["p"])
		inside += leg["stay"]
		at = leg["p"]
	metres += at.distance_to(home)
	var speed: float = outing["pace"] if outing["pace"] > 0.0 else NPCRoutine.pace(npc.id)
	return inside + int(metres * NPCRoutine.DETOUR / speed * SimClock.TICKS_PER_SECOND)

## Everyone this system runs, found once; `settle` also puts them where their
## routine says they are right now.
func _enrol(entities: Dictionary, tick: int, settle: bool) -> void:
	_seen_entities = entities.size()
	for entity in entities.values():
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc.is_cop or npc.is_crew or npc.is_down or entity.has_component(ComponentNames.PLAYER_STATE):
			continue
		if _enrolled.has(npc.id) and not settle:
			continue
		_enrolled[npc.id] = npc
		_lead[npc.id] = _walk_ticks(npc)
		_plan_day(npc, tick)
		if settle:
			_settle(npc, tick)

func _resync(entities: Dictionary, tick: int) -> void:
	_due.clear()
	street.clear()
	for book in [_from, _homebound, _visit_until, _outing_at, _routine_wake]:
		book.clear()
	_enrol(entities, tick, true)

## Puts one person where they would be by now: inside (or outside the door, for
## those who hang around), unless they should only just have set off.
func _settle(npc: NPCData, tick: int) -> void:
	var door: Variant = street.final_of(npc.id)
	if door == null:
		return
	street.place_at_end(npc, door)
	if _just_left(npc, tick):
		npc.position = _from.get(npc.id, door)
		street.step_out(npc)
	elif NPCRoutine.stays_outside(npc, tick):
		npc.position = door
		street.step_out(npc)
	else:
		street.put_inside(npc, door)
		if _homebound.has(npc.id):
			_think_about_going_out(npc, tick)

## Decides what this person should be doing now; called when something changes
## for them (shift start or end, a visit over, time to think about going out),
## never per tick. Safe to call at any time: it only acts on what has changed.
func _plan_day(npc: NPCData, tick: int) -> void:
	var window := _work_window(npc, tick)   # x: ticks into it (or past it), y: its length, both from departure
	var in_window := window.x < window.y
	var day_off := not npc.is_dealer and NPCOutings.takes_day_off(npc.id, _shift_day(npc, tick))
	var heading_to_work := _has_building(npc.work_building_id) and in_window and not day_off
	var target_id: StringName = npc.work_building_id if heading_to_work else npc.home_building_id
	var from_id: StringName = npc.home_building_id if heading_to_work else npc.work_building_id
	var until_change := maxi(1, (window.y if in_window else SimClock.day_ticks) - window.x)
	var routine := tick + mini(until_change, NPCRoutine.ticks_to_loiter_edge(npc, tick))
	if _routine_wake.get(npc.id, NEVER) != routine:
		_routine_wake[npc.id] = routine
		_wake(npc, routine)
	if not _has_building(target_id):
		street.forget_trip(npc.id)
		return
	var door: Vector2 = _door(target_id)
	if _has_building(from_id):
		_from[npc.id] = _door(from_id)
	if heading_to_work:
		_homebound.erase(npc.id)
		_visit_until.erase(npc.id)   # work calls: whatever they were doing is over
		_outing_at.erase(npc.id)
	else:
		_homebound[npc.id] = true
	if street.final_of(npc.id) != door:
		street.start_trip(npc, NPCOutings.via(npc.id, _shift_day(npc, tick), npc.position, door), door, 0.0)
	elif _visit_until.has(npc.id):
		if tick >= _visit_until[npc.id]:   # done in the shop: on to the next stop (home, in the end)
			_visit_until.erase(npc.id)
			street.next_leg(npc)
			street.step_out(npc)
	elif npc.indoors and not heading_to_work and tick >= _outing_at.get(npc.id, tick + 1):
		var free := SimClock.day_ticks - window.x if _has_building(npc.work_building_id) and not in_window else SimClock.day_ticks
		_maybe_go_out(npc, door, tick, free)
	elif npc.indoors and NPCRoutine.stays_outside(npc, tick):
		street.step_out(npc)   # morning: the ones who hang around come back out

## Which working day `tick` belongs to for this person (changes when they would
## set off for work, so one day's choices hold from leaving home to the next leaving).
func _shift_day(npc: NPCData, tick: int) -> int:
	var opened := int(NPCRoutine.shift_of(npc).x * SimClock.day_ticks) - int(_lead.get(npc.id, 0))
	return floori(float(tick - opened) / SimClock.day_ticks)

func _has_building(id: StringName) -> bool:
	return id != &"" and _world.entities.has(id)

func _door(id: StringName) -> Vector2:
	return _world.entities[id].get_component(ComponentNames.BUILDING).position

## Ticks this person's walk between home and work takes at their pace.
func _walk_ticks(npc: NPCData) -> int:
	if not (_has_building(npc.home_building_id) and _has_building(npc.work_building_id)):
		return 0
	var seconds := _door(npc.home_building_id).distance_to(_door(npc.work_building_id)) * NPCRoutine.DETOUR / NPCRoutine.pace(npc.id)
	return mini(int(seconds * SimClock.TICKS_PER_SECOND), SimClock.hours(NPCRoutine.MAX_LEAD_HOURS))

## The stretch of the day this person is at work or walking there: it opens when
## they must leave home to be on time and closes at the end of the shift.
## Returns (ticks since it opened, its length in ticks).
func _work_window(npc: NPCData, tick: int) -> Vector2i:
	var shift := NPCRoutine.shift_of(npc)
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

func _player_position() -> Vector2:
	for entity in _world.get_entities_with_component(ComponentNames.PLAYER_STATE).values():
		return entity.get_component(ComponentNames.NPC).position
	return Vector2.INF   # no player (some checks): everyone is "far"
