## NB2c: free time run by the shared brain, used by NPCScheduleSystem when
## GameRules.brain is on (NPCOutings' coin flips when it is off). When someone
## at home thinks about going out, ActivityChooser picks what they feel like;
## this turns the pick into a trip (shop visit, stroll, standing on the stoop,
## or staying in), and once the trip starts, fills the needs it serves and
## remembers it as the habit for that time of day.
## Seeded from (person, day, quarter hour), never the shared random stream.
## Trips are paid for in time only; nobody's cash changes yet.
class_name NPCFreeTime
extends RefCounted

const SALT_TRIP := 9500
const SLOT_HOURS := 0.25       # a fresh pick each quarter hour of the day
const NIGHT_ENDS_H := 4.0      # the first pick after this hour finds them rested
const BREAKFAST := 0.7         # and fed at least this well
const HABIT_SLOT_H := 4.0      # habits are kept per 4-hour slot

var places := ActivityPlaces.new()
var picks := {}                # activity id -> trips started (checks, soak numbers)
var _outings: NPCOutings

func _init(outings: NPCOutings) -> void:
	_outings = outings

## The same random numbers for the same person, day and quarter hour.
static func rng_for(npc_id: StringName, tick: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([npc_id, SimClock.day_number(tick), _slot(tick), SALT_TRIP])
	return rng

static func _slot(tick: int) -> int:
	return int(posmod(tick, SimClock.day_ticks) / maxi(1, SimClock.hours(SLOT_HOURS)))

## What they will do now: {activity, legs, pace, hold} (legs [] and hold 0 =
## stay in), or {} if nothing is possible. Makes their mind if they have none
## and lets a passed night rest them; their needs are not filled until started().
func plan(world: World, npc: NPCData, home: Vector2, tick: int) -> Dictionary:
	var entity: Entity = world.entities.get(npc.id)
	if entity == null:
		return {}
	var mind := NPCMind.get_or_make(world, entity)
	night_rest(npc.id, mind, tick)
	var where := places.for_person(world, npc, mind)
	var scored := ActivityChooser.score_all(npc, mind, tick, where, habit(mind, tick))
	var id := ActivityChooser.pick(scored, npc.id, SimClock.day_number(tick), _slot(tick))
	if id == &"":
		return {}
	return _trip(id, where[id][1], home, rng_for(npc.id, tick))

func _trip(id: StringName, at: Vector2, home: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var a: Dictionary = Activities.TABLE[id]
	var stay := SimClock.hours(rng.randf_range(a["stay"][0], a["stay"][1]) / 60.0)
	var out := {"activity": id, "legs": [], "pace": 0.0, "hold": 0}
	match a["walk"]:
		"visit":
			out["legs"] = [{"p": at, "stay": maxi(1, stay)}]
		"stroll":
			var walk := _outings.promenade(home, rng)
			out["legs"] = walk["legs"]
			out["pace"] = walk["pace"]
		"linger":
			out["hold"] = maxi(1, stay)   # stand at their own door, then back in
	return out

## The trip has started: the needs it serves are filled and it becomes the
## habit for this time of day.
func started(world: World, npc: NPCData, outing: Dictionary, tick: int) -> void:
	var mind := NPCMind.get_or_make(world, world.entities[npc.id])
	var id: StringName = outing["activity"]
	var fills: Dictionary = Activities.TABLE[id]["fills"]
	mind.drives = NPCMind.drives_now(npc.id, mind, tick)
	for k in fills:
		mind.drives[k] = clampf(mind.drives[k] + float(fills[k]), 0.0, 1.0)
	mind.drives_tick = tick
	if mind.habit_slots.size() != NPCMind.HABIT_SLOTS:
		mind.habit_slots.resize(NPCMind.HABIT_SLOTS)
	mind.habit_slots[_habit_slot(tick)] = String(id)
	picks[id] = picks.get(id, 0) + 1

## What they did last time at this time of day (&"" if nothing yet).
static func habit(mind: NPCMindData, tick: int) -> StringName:
	var i := _habit_slot(tick)
	return StringName(mind.habit_slots[i]) if i < mind.habit_slots.size() else &""

static func _habit_slot(tick: int) -> int:
	return clampi(int(SimClock.day_fraction(tick) * 24.0 / HABIT_SLOT_H), 0, NPCMind.HABIT_SLOTS - 1)

## A night has passed since their needs were last set: they slept and ate at
## home, so they start the day rested and fed.
static func night_rest(npc_id: StringName, mind: NPCMindData, tick: int) -> void:
	var night_end := (SimClock.day_number(tick) - 1) * SimClock.day_ticks + SimClock.hours(NIGHT_ENDS_H)
	if tick < night_end or mind.drives_tick >= night_end:
		return
	mind.drives = NPCMind.drives_now(npc_id, mind, tick)
	mind.drives[GanstoidEnums.MindDrive.ENERGY] = 1.0
	mind.drives[GanstoidEnums.MindDrive.FOOD] = maxf(mind.drives[GanstoidEnums.MindDrive.FOOD], BREAKFAST)
	mind.drives_tick = tick
