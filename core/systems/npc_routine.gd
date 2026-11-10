## The rules of a civilian's day, as pure functions of who they are and what time
## it is (S1, split out of NPCScheduleSystem in S3c). No state: everything is
## rolled from the person's id, so the same person keeps the same habits.
##
## - Shifts on the real clock: most people work days (start 06:30-09:30, 8.5 h),
##   some evenings (14:00-16:00, 8 h), a few nights (22:00-23:30, 8 h). Dealers
##   work the corner from mid-afternoon to about 02:00.
## - A few people (LOITERER_SHARE) hang around outside their door by day instead
##   of going in; dealers stay out on their corner while working.
## - Everyone walks at their own pace (1.25-1.65 m/s).
## - The reckless few (DARK_SHARE) cut through yards, lots and alleys at night.
class_name NPCRoutine
extends RefCounted

## [earliest start hour, latest start hour, shift length in hours, share of civilians]
const SHIFTS := [[6.5, 9.5, 8.5, 0.78], [14.0, 16.0, 8.0, 0.14], [22.0, 23.5, 8.0, 0.08]]
const DEALER_SHIFT := [15.0, 17.0, 10.0]
const LOITER_FROM_HOUR := 7.0
const LOITER_TO_HOUR := 22.0
const LOITERER_SHARE := 0.08       # civilians who stay outside their door instead of going in
const DARK_SHARE := 0.12           # addicts, thugs, the reckless: cut through anywhere at night
const NIGHT_FROM := 21.0
const NIGHT_TO := 5.0
const DETOUR := 1.35               # streets are longer than the straight line
const MAX_LEAD_HOURS := 3.0        # nobody sets off more than this before their shift
const PACE_MIN := 1.25             # m/s; SimUnits.WALK (1.5) is the middle of the range
const PACE_MAX := 1.65

## [start, length] of this person's shift as fractions of a day.
static func shift_of(npc: NPCData) -> Vector2:
	var roll := unit(npc.id, 1)
	var row: Array = DEALER_SHIFT
	if not npc.is_dealer:
		var acc := 0.0
		for candidate in SHIFTS:
			row = candidate
			acc += candidate[3]
			if roll < acc:
				break
	var start: float = lerpf(row[0], row[1], unit(npc.id, 2))
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
	return is_loiterer(npc) and hour >= LOITER_FROM_HOUR and hour < LOITER_TO_HOUR

static func is_loiterer(npc: NPCData) -> bool:
	return not npc.is_dealer and unit(npc.id, 3) < LOITERER_SHARE

## Ticks until the hour loiterers come out or go in (a day for everyone else).
static func ticks_to_loiter_edge(npc: NPCData, tick: int) -> int:
	if not is_loiterer(npc):
		return SimClock.day_ticks
	var now := SimClock.day_fraction(tick)
	var best := 1.0
	for hour in [LOITER_FROM_HOUR, LOITER_TO_HOUR]:
		var gap := fposmod(hour / 24.0 - now, 1.0)
		if gap > 0.0:
			best = minf(best, gap)
	return maxi(1, int(ceil(best * SimClock.day_ticks)))

static func pace(npc_id: StringName) -> float:
	return lerpf(PACE_MIN, PACE_MAX, unit(npc_id, 4))

## Civilians keep to public ground; dealers know the shortcuts.
static func home_layer(npc: NPCData) -> String:
	return "full" if npc.is_dealer else "public"

## At night the reckless few stop keeping to the sidewalk: yards, lots and
## alleys are all fair game. They are who the player meets in the dark places.
static func layer_at(npc: NPCData, tick: int) -> String:
	if npc.is_dealer:
		return "full"
	var hour := SimClock.day_fraction(tick) * 24.0
	if is_dark_route(npc.id) and (hour >= NIGHT_FROM or hour < NIGHT_TO):
		return "full"
	return "public"

static func is_dark_route(npc_id: StringName) -> bool:
	return unit(npc_id, 11) < DARK_SHARE

## Stable 0..1 number from an id; `salt` gives independent rolls for one person.
static func unit(npc_id: StringName, salt: int) -> float:
	return float(absi(hash([npc_id, salt])) % 10007) / 10007.0
