## BZ7: your empire as a whole. What you own, what each place is
## (EmpireSystem.describe, for the city map and the phone), what it brought
## in yesterday (the Empire page), and the other side of owning things:
## rivals strike back. Each morning every rival lieutenant hunting you
## (RivalSystem.HUNT or more) may hit one of your places (HIT_CHANCE):
##   a shop or front  the till and some of the bank are taken
##   a night spot     smashed up: a step of its fit-out gone, no take tonight
##   a ring or a den  robbed: no take tonight
## Protection (multiplied): a bouncer there, your own security firm, crew
## posted within GUARD_R. A hit vents some of his grudge, comes as a message
## and a stamp, shows on the map, and makes the paper.
class_name EmpireSystem
extends SystemBase

const EVERY := 60
const PHASE := 21
const HIT_CHANCE := 0.25
const BOUNCER_KEEP := 0.5
const CREW_KEEP := 0.5
const GUARD_R := 120.0
const BANK_TAKE := 300
const VENT := 15.0
const HIT_SHOWN_DAYS := 3
const FRONT_LETTER := {"car_wash": "W", "laundromat": "L", "restaurant": "R", "trucking": "T", "security": "S"}

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _day := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	var day := HustleSystem.day_of(tick)
	if day == _day:
		return
	var first := _day == -1
	_day = day
	if first:
		return
	for p in entities.values():
		strike_back(_world, p.get_component(ComponentNames.PLAYER_STATE), day)

## Every building that's yours to lose (not your home).
static func places(world: World, state: PlayerStateData) -> Array:
	var out: Array = []
	for b in BusinessSystem.player_owned(world):
		out.append(b.id)
	for id in state.properties:
		if not out.has(id):
			out.append(id)
	return out

## [letter, colour, label, open] for a place of yours on the map and the phone.
static func describe(world: World, state: PlayerStateData, b: BuildingData) -> Array:
	var hit: Dictionary = state.empire_hits.get(b.id, {})
	var note := ""
	if not hit.is_empty() and HustleSystem.day_of(world.tick) - int(hit["day"]) <= HIT_SHOWN_DAYS:
		note = " · hit by %s" % hit["by"]
	if state.venues.has(b.id):
		var v: Dictionary = state.venues[b.id]
		return ["N", Color("b07ae8"), "%s (%s)%s" % [VenueSystem.KINDS[v["kind"]][0], Grades.venue(VenueSystem.stars(state, b.id)), note], true]
	if state.fronts.has(b.id):
		var k: String = state.fronts[b.id]
		return [FRONT_LETTER.get(k, "F"), Color("4fc3a1"), "%s%s" % [FrontSystem.KINDS[k][0], note], true]
	if state.rings.has(b.id):
		var open: bool = state.rings[b.id].get("open", false)
		return ["G", Color("e0704a"), "Stolen-goods ring%s%s" % ["" if open else " (shut by the police)", note], open]
	if state.dens.has(b.id):
		var open: bool = state.dens[b.id].get("open", false)
		return ["D", Color("e0704a"), "Gambling den%s%s" % ["" if open else " (shut by the police)", note], open]
	if state.properties.has(b.id):
		return ["P", Color("8fb3d9"), "A flat you rent out%s" % note, true]
	return ["$", Color(0.45, 0.85, 0.42), "Your %s%s" % [String(b.trade if b.trade != &"" else &"shop"), note], true]

## How much of a hit gets through at this place (1 = unguarded).
static func exposure(world: World, state: PlayerStateData, b: BuildingData) -> float:
	var keep := FrontSystem.guard_mult(state)
	if VenueSystem.has_bouncer(state, b.id):
		keep *= BOUNCER_KEEP
	for id in state.crew_ids:
		var e: Entity = world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and n.crew_role != GanstoidEnums.CrewRole.UNASSIGNED and n.position.distance_to(b.position) <= GUARD_R:
			keep *= CREW_KEEP
			break
	return keep

## Each morning: rivals hunting you may hit a place of yours.
static func strike_back(world: World, state: PlayerStateData, day: int) -> void:
	var rng := world.runtime_rng
	var mine := places(world, state)
	if mine.is_empty():
		return
	for g in state.rivals:
		var r: Dictionary = state.rivals[g]
		if float(r.get("grudge", 0.0)) < RivalSystem.HUNT:
			continue
		var id: StringName = mine[rng.randi() % mine.size()]
		var e: Entity = world.entities.get(id)
		var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
		if b == null or rng.randf() >= HIT_CHANCE * exposure(world, state, b):
			continue
		hit(world, state, b, String(r.get("name", "A rival")), day)
		r["grudge"] = maxf(0.0, float(r["grudge"]) - VENT)

## What a hit does to a place.
static func hit(world: World, state: PlayerStateData, b: BuildingData, by: String, day: int) -> void:
	var lost := 0
	var what := "hit"
	if state.venues.has(b.id):
		var v: Dictionary = state.venues[b.id]
		v["decor"] = maxi(0, int(v["decor"]) - 1)
		v["closed_until"] = day + 1
		what = "smashed up"
	elif state.rings.has(b.id) or state.dens.has(b.id):
		var r: Dictionary = state.rings.get(b.id, state.dens.get(b.id, {}))
		r["closed_until"] = day + 1
		lost = int(r.get("last", 0))
		what = "robbed"
	else:
		lost = b.cash_on_hand + mini(b.bank, BANK_TAKE)
		b.bank -= mini(b.bank, BANK_TAKE)
		b.cash_on_hand = 0
		b.has_been_hit = true
		what = "robbed"
	state.empire_hits[b.id] = {"day": day, "by": by, "lost": lost}
	var label: String = describe(world, state, b)[2].split(" · ")[0]
	PhoneSystem.push(world, state, by, "Nice place you had. Your %s. Next time it's you." % label.to_lower())
	StampView.put(state, "HIT", "%s %s your %s" % [by, what, label.to_lower()], UiTheme.BAD)
	StreetTalk._count(world, state, "empire_hit", lost)

## A place of yours closed for tonight after a hit?
static func closed(world: World, rec: Dictionary) -> bool:
	return HustleSystem.day_of(world.tick) < int(rec.get("closed_until", -1))
