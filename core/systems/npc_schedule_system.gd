## Two-state civilian schedule (roadmap Phase 1 locked shape spec): work
## during the first WORK_FRACTION of a day-tick cycle, home the rest.
## Unemployed NPCs just stay near home (no work_building_id to route to).
## Dealers (Phase 2) run through here too, deliberately not special-cased
## out -- their work_building_id just happens to be an ILLEGAL_FRONT lot
## instead of a LEGIT_BUSINESS one, which is all it takes to make them
## walk the same day/night cycle as everyone else. See
## PopulationSeeder._seed_dealers for the gameplay reasoning.
##
## Phase 2 batch 4 (locked): two realism passes on top of the plain
## dead-reckon commute, both existing purely to make crowd density around
## any one spot fluctuate instead of being perfectly predictable --
## otherwise a dealer's street corner is either "always exactly this many
## people, right on the tick" or "always empty," and there's no scene left
## for the player to actually read before deciding to deal.
## 1. Per-NPC schedule stagger (schedule_offset): each NPC's work<->home
##    flip is jittered by a deterministic hash of their own id, not one
##    global tick for the whole population -- arrivals/departures spread
##    out over a window instead of every NPC moving in lockstep.
## 2. Idle wander: once "arrived," an NPC doesn't freeze on the building's
##    exact pixel -- they drift within IDLE_WANDER_RADIUS of it, via the
##    shared WanderBehavior utility (also used by CopAISystem's patrol,
##    Phase 2 batch 5), so the headcount near that pixel at any given
##    moment is never a fixed, lookup-able number.
##
## Unlike most systems, this one takes World in its constructor purely to
## call World.reindex_position after moving an entity -- SystemBase.
## process_entities only hands a system the entities dict, which is enough
## for systems that just read/mutate components, but moving an entity has a
## second step (telling World's spatial index) that needs World itself.
## PlayerInputSystem and CopAISystem follow the same pattern for the same
## reason; RecognitionSystem and others that never move anything stay
## World-agnostic, which is still the default/simpler case.
##
## Stored as a WeakRef (_world_ref), not a direct reference -- World holds
## this system in its _hot_systems array, so a direct System -> World
## reference back would be a retain cycle (RefCounted doesn't collect
## cycles; caught by the headless run leaking the entire World graph at
## exit). The `_world` property below resolves the weakref on each access,
## so every other line in this file reads exactly as if it were a normal
## field.
class_name NPCScheduleSystem
extends SystemBase

const DAY_LENGTH_TICKS := 1800  # ~30 sim-seconds at 60 tick/s -- short enough to see a full day cycle quickly
const WORK_FRACTION := 0.6
const WALK_SPEED := 60.0
const ARRIVE_EPSILON := 4.0

## +/- range for the per-NPC schedule jitter, in ticks. Big enough to
## visibly spread 130 NPCs' commute times apart, small enough that "work"
## still basically means "daytime" for everyone -- this isn't meant to
## scramble the day/night read, just stop it being perfectly synchronized.
const STAGGER_RANGE_TICKS := 240  # +/- 4 sim-seconds at 60 tick/s

## Idle wander: how far an "arrived" NPC drifts around their destination,
## how fast they stroll while doing it (slower than a purposeful commute),
## and how long they pause between picking a new drift point. Passed into
## WanderBehavior.advance each tick rather than being WanderBehavior's own
## constants, since CopAISystem's patrol wander wants different numbers
## for the same behavior.
const IDLE_WANDER_RADIUS := 48.0
const IDLE_WALK_SPEED := 24.0
const IDLE_DWELL_MIN_TICKS := 60   # 1 sim-second
const IDLE_DWELL_MAX_TICKS := 360  # 6 sim-seconds

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

## Per-NPC idle-wander state (StringName -> Vector2 / StringName -> int),
## owned here and passed into WanderBehavior.advance by reference every
## tick -- see WanderBehavior's doc comment for why it doesn't hold this
## state itself. Only ever populated for NPCs currently idling at a
## destination, not every NPC every tick.
var _idle_targets: Dictionary = {}
var _idle_dwell_until: Dictionary = {}

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.NPC

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	for entity in entities.values():
		if entity.has_component(ComponentNames.PLAYER_STATE):
			continue  # the player drives their own movement -- see PlayerInputSystem
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc.is_cop:
			continue  # cops patrol under CopAISystem instead
		if npc.is_crew:
			continue  # crew move under CrewSystem (batch 15)
		if npc.is_busy:
			continue  # mid-handoff with the player (batch 11) -- stays put until the deal resolves
		var target: Variant = _target_position(npc, tick)
		if target == null:
			continue  # no valid home/work building found -- shouldn't happen post-PopulationSeeder, but don't crash if it does
		if npc.position.distance_to(target) <= IDLE_WANDER_RADIUS:
			npc.position = WanderBehavior.advance(
				npc.id, npc.position, target, IDLE_WANDER_RADIUS, IDLE_WALK_SPEED,
				IDLE_DWELL_MIN_TICKS, IDLE_DWELL_MAX_TICKS, delta, tick,
				_idle_targets, _idle_dwell_until, ARRIVE_EPSILON
			)
			_world.reindex_position(npc.id)
		else:
			# Still commuting -- drop any stale idle state from the *previous*
			# destination so arriving at the new one starts idling fresh.
			WanderBehavior.clear(npc.id, _idle_targets, _idle_dwell_until)
			npc.position = WanderBehavior.step_toward(npc.position, target, WALK_SPEED, delta, ARRIVE_EPSILON)
			_world.reindex_position(npc.id)

func _target_position(npc: NPCData, tick: int) -> Variant:
	var staggered_tick := tick + schedule_offset(npc.id)
	var day_fraction := float(posmod(staggered_tick, DAY_LENGTH_TICKS)) / float(DAY_LENGTH_TICKS)
	var at_work := day_fraction < WORK_FRACTION and npc.work_building_id != &""
	var target_id: StringName = npc.work_building_id if at_work else npc.home_building_id
	if target_id == &"" or not _world.entities.has(target_id):
		target_id = npc.home_building_id
	if target_id == &"" or not _world.entities.has(target_id):
		return null
	var building: BuildingData = _world.entities[target_id].get_component(ComponentNames.BUILDING)
	return building.position

## Deterministic per-NPC jitter derived from their id -- no new NPCData
## field needed, and automatically stable/reproducible for a given city
## seed (same npc ids -> same offsets every run, so this never undermines
## WorldGenerator's seeded determinism). Public (not prefixed `_`) so
## debug/verify_phase2_dealer_schedule.gd can account for it directly
## instead of duplicating the formula.
static func schedule_offset(npc_id: StringName) -> int:
	return (absi(hash(npc_id)) % (2 * STAGGER_RANGE_TICKS + 1)) - STAGGER_RANGE_TICKS
