## S2: what civilians do with their free time, and why no two walks look alike.
##
## A life of home -> work -> home leaves the streets empty at midday and in the
## evening, and gives the player nobody to watch, follow or rob. So people also:
##   run an errand   walk to a nearby business, go in for a while, walk home
##   go out          the same in the evening, staying much longer
##   promenade       a stroll with no destination: two or three turns around
##                   the neighbourhood at an easy pace, alone, then home.
##                   A few night owls do this late; they are the lone figures
##                   on a dark street.
## And nobody walks like a script:
##   - about a third of people are creatures of habit and always take the same
##     way; the rest have two or three ways and the choice changes by the day
##   - some days a person does not go to work at all
##   - how often someone goes out, how far, and how fast is their own
##
## NPCScheduleSystem owns movement and calendars; this file only decides what an
## outing is. No state of its own beyond the shops near each home.
class_name NPCOutings
extends RefCounted

enum Kind { ERRAND, EVENING_OUT, PROMENADE }

const MEAN_GAP_HOURS := 9.0        # average free time between one person's outings
const MIN_GAP_HOURS := 0.4
const HOMEBODY_SHARE := 0.15       # never go out for no reason
const STROLLER_SHARE := 0.3        # prefer a walk to a shop
const NIGHT_OWL_SHARE := 0.1       # the ones still out walking after everyone has gone in
const DAY_OFF_CHANCE := 0.12       # per person per day: not going in today
const HABIT_SHARE := 0.35          # always the same route

const DAY_FROM := 7.0
const ERRAND_UNTIL := 20.0
const EVENING_FROM := 18.0
const BEDTIME := 23.0              # ordinary people do not set out after this
const OWL_BEDTIME := 3.0

const ERRAND_STAY_MIN := [8.0, 30.0]       # game minutes inside
const EVENING_STAY_MIN := [40.0, 120.0]
const SHOPS_SAMPLED := 40
const SHOPS_KEPT := 4
const SHOP_MAX_M := 450.0

const STROLL_LEG_M := [90.0, 260.0]        # each turn of a promenade
const STROLL_TURNS := [2, 3]
const STROLL_PACE := [0.9, 1.2]            # m/s

const VIA_SIDE_SHARE := [0.18, 0.4]        # how far off the straight line an alternative way swings
const VIA_MAX_M := 220.0
const VIA_MIN_TRIP_M := 120.0              # shorter walks have no meaningful alternative

var _shops := {}   # home door -> Array[Vector2] of business doors near it
var _businesses: Dictionary = {}   # MAP1: Vector2i cell (SHOP_MAX_M square) -> business doors in it
var _businesses_for := -1

## Ticks until this person next thinks about going out.
static func next_gap(npc_id: StringName, rng: RandomNumberGenerator) -> int:
	var keen := lerpf(0.6, 1.8, unit(npc_id, 21))   # some people are out twice as often as others
	var hours := MIN_GAP_HOURS + -log(maxf(rng.randf(), 0.0001)) * (MEAN_GAP_HOURS - MIN_GAP_HOURS) / keen
	return SimClock.hours(hours)

static func is_homebody(npc_id: StringName) -> bool:
	return unit(npc_id, 22) < HOMEBODY_SHARE

static func is_night_owl(npc_id: StringName) -> bool:
	return unit(npc_id, 23) < NIGHT_OWL_SHARE

static func takes_day_off(npc_id: StringName, day: int) -> bool:
	return unit_day(npc_id, day, 24) < DAY_OFF_CHANCE

## An outing for this person at this hour: {kind, legs: [{p, stay}], pace} or {}.
## `legs` are the stops before home; stay is ticks indoors (0 = just walk past).
func plan(world: World, npc: NPCData, home: Vector2, hour: float, rng: RandomNumberGenerator) -> Dictionary:
	if is_homebody(npc.id):
		return {}
	var owl := is_night_owl(npc.id)
	var late := hour >= BEDTIME or hour < DAY_FROM
	if late and not (owl and (hour >= BEDTIME or hour < OWL_BEDTIME)):
		return {}
	var stroller := unit(npc.id, 25) < STROLLER_SHARE
	if late or rng.randf() < (0.65 if stroller else 0.25):
		return _promenade(home, rng)
	var shops := _shops_near(world, home, rng)
	if shops.is_empty():
		return _promenade(home, rng)
	var evening := hour >= EVENING_FROM
	if not evening and hour >= ERRAND_UNTIL:
		return _promenade(home, rng)
	var stay: Array = EVENING_STAY_MIN if evening and rng.randf() < 0.7 else ERRAND_STAY_MIN
	var door: Vector2 = shops[rng.randi() % shops.size()]
	return {"kind": Kind.EVENING_OUT if stay == EVENING_STAY_MIN else Kind.ERRAND, "pace": 0.0,
		"legs": [{"p": door, "stay": SimClock.hours(rng.randf_range(stay[0], stay[1]) / 60.0)}]}

func _promenade(home: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var legs := []
	var at := home
	var heading := rng.randf() * TAU
	for i in rng.randi_range(STROLL_TURNS[0], STROLL_TURNS[1]):
		heading += rng.randf_range(-1.4, 1.4)   # wander on, do not double straight back
		at += Vector2.from_angle(heading) * rng.randf_range(STROLL_LEG_M[0], STROLL_LEG_M[1])
		var spot := at
		if SimNav.active != null:
			spot = SimNav.active.snap(at, "public")
		legs.append({"p": spot, "stay": 0})
	return {"kind": Kind.PROMENADE, "legs": legs, "pace": rng.randf_range(STROLL_PACE[0], STROLL_PACE[1])}

## MAP1: the business doors bucketed by area, so a 21,000-building map is walked
## once (at new game: NPCScheduleSystem.settle_all), never on a tick.
func prime(world: World) -> void:
	var buildings := world.get_entities_with_component(ComponentNames.BUILDING)
	if _businesses_for == buildings.size():
		return
	_businesses_for = buildings.size()
	_businesses.clear()
	for entity in buildings.values():
		var b: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			_businesses.get_or_add(Vector2i((b.position / SHOP_MAX_M).floor()), []).append(b.position)

## The few businesses someone living at `home` actually uses: the nearest of a
## sample of the district's businesses (nobody knows every shop in town).
func _shops_near(world: World, home: Vector2, rng: RandomNumberGenerator) -> Array:
	if _shops.has(home):
		return _shops[home]
	prime(world)
	var near: Array[Vector2] = []
	var c := Vector2i((home / SHOP_MAX_M).floor())
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			near.append_array(_businesses.get(Vector2i(x, y), []))
	var seen := []
	for i in mini(SHOPS_SAMPLED, near.size()):
		var door: Vector2 = near[rng.randi() % near.size()]
		if door.distance_to(home) <= SHOP_MAX_M and not seen.has(door):
			seen.append(door)
	seen.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(home) < b.distance_squared_to(home))
	_shops[home] = seen.slice(0, SHOPS_KEPT)
	return _shops[home]

## The way someone walks from a to b today: [] for straight there, or one stop
## to pass through first. Creatures of habit always get []. Everyone else has a
## left-hand and a right-hand alternative and today's roll picks between the
## three, so the same commute looks different on different days.
static func via(npc_id: StringName, day: int, a: Vector2, b: Vector2) -> Array:
	var trip := a.distance_to(b)
	if trip < VIA_MIN_TRIP_M or unit(npc_id, 26) < HABIT_SHARE:
		return []
	var roll := unit_day(npc_id, day, 27)
	if roll < 0.4:
		return []
	var side := 1.0 if roll < 0.7 else -1.0
	var swing := minf(VIA_MAX_M, trip * lerpf(VIA_SIDE_SHARE[0], VIA_SIDE_SHARE[1], unit(npc_id, 28)))
	var along := lerpf(0.35, 0.65, unit(npc_id, 29))
	var p := a.lerp(b, along) + (b - a).normalized().orthogonal() * swing * side
	if SimNav.active != null:
		p = SimNav.active.snap(p, "public")
	return [{"p": p, "stay": 0}]

## Stable 0..1 number from an id; `salt` gives independent rolls for one person.
static func unit(npc_id: StringName, salt: int) -> float:
	return float(absi(hash([npc_id, salt])) % 10007) / 10007.0

static func unit_day(npc_id: StringName, day: int, salt: int) -> float:
	return float(absi(hash([npc_id, day, salt])) % 10007) / 10007.0
