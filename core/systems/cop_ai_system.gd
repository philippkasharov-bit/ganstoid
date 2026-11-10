## Low difficulty tier cop AI (roadmap Phase 5 spec): patrol + reactive
## arrest, nothing proactive yet. A cop wanders near its depot until a
## crime is reported close enough to hear about it (BROADCAST_RADIUS), then
## heads toward the PLAYER's current position -- not the stale crime
## location -- so it reads as "coming for you," not "walking to a cold
## spot on the map." Reaching arrest range while the player is still
## WARNED applies the Phase 1 "short jail stint" stub: law_tier resets to
## CLEAN and the player is sent home. Losing the tier (decayed, or already
## arrested by another cop) makes a cop stand down and resume patrol.
##
## Phase 2 batch 5 (locked): patrol realism, the cop-side counterpart to
## batch 4's civilian idle wander. Two fixes, both via the shared
## WanderBehavior utility (see its doc comment):
## 1. Leashed wander (was unleashed): the old patrol logic re-anchored each
##    new wander target at the cop's OWN CURRENT position, not their
##    depot -- a pure random walk with no restoring force, so over a long
##    enough session a cop could drift arbitrarily far from post. Patrol
##    now anchors every wander target at the cop's home_building_id
##    position (the same "depot" PopulationSeeder already gives every cop
##    as a patrol origin), so PATROL_WANDER_RADIUS is now an actual leash,
##    not just the step size of an unbounded walk.
## 2. Patrol dwell pauses (new): a patrolling cop now pauses for a
##    randomized window between picking new wander points, same idea as a
##    civilian's idle dwell -- real gaps in coverage, not constant if
##    random motion, which is what actually gives "catch the dealer out in
##    public" any tension at all.
##
## Phase 2 batch 6 (locked): the "more guarded" half of the robbed-corner
## feedback loop. A cop whose depot is near a building that's ever been
## robbed (BuildingData.has_been_hit, set by CrimeSystem.rob_building via
## EconomySystem.apply_robbery) re-anchors their patrol wander at that
## building instead of their own depot, tighter and more often -- see
## GUARD_BIAS_RADIUS's doc comment below. Still routed entirely through
## _advance_patrol's own movement math; does not touch _alerted or
## on_crime_witnessed at all.
##
## IMPORTANT, locked design constraint (see roadmap "Evidence-gated law
## response"): none of this changes WHEN a cop reacts, only how it moves
## while NOT reacting. The only path into `_alerted` is on_crime_witnessed,
## fired only by the existing witnessed+recognized CRIME_WITNESSED event --
## there is still no "cop is near the player" check anywhere in this file,
## and there must never be one. A smarter/less-scripted patrol is explicitly
## in scope; a patrol that can itself trigger a response by proximity is not.
## Guarding a robbed building tighter is also not a proximity-trigger --
## has_been_hit only ever gets set by a witnessed-and-recognized robbery,
## same evidence gate as every other crime consequence.
##
## Phase 2 batch 10 (locked): generalizes the above from "robbery only"
## to "patrol high crime places" -- BuildingData.crime_heat (any witnessed
## crime type, not just robbery) replaces has_been_hit as the guard-tier
## trigger, and a new, higher raid tier fires a one-time bust event (gang
## cash/standing hit, if it's gang turf) once a RAIDABLE building's heat
## clears a second, much higher threshold -- "only raid if there's a bunch
## of evidence," per Phil's explicit request. Still routed entirely through
## _advance_patrol's movement math and the same crime_heat writer
## (CrimeSystem._bump_crime_heat, itself gated the same way CRIME_WITNESSED
## is); the raid never touches the player directly or _alerted at all.
class_name CopAISystem
extends SystemBase

const PATROL_SPEED := SimUnits.WALK
const RESPONSE_SPEED := SimUnits.SPRINT
const PATROL_WANDER_RADIUS := 150.0   # metres around the depot
const PATROL_DWELL_MIN_TICKS := 120  # 2 sim-seconds
const PATROL_DWELL_MAX_TICKS := 480  # 8 sim-seconds
const ARRIVE_EPSILON := SimUnits.ARRIVE_M

## Batch 6 (locked): the "more guarded" half of EconomySystem.apply_robbery's
## reserved feedback loop -- a cop whose depot is within GUARD_BIAS_RADIUS of
## a building that's ever been robbed (BuildingData.has_been_hit) re-anchors
## their patrol wander at that building instead of their own depot, with a
## tighter radius and shorter dwell: a real, visible "this corner gets
## watched closer now" response, not a stat-only consequence. Checked fresh
## every time a cop is about to pick a new wander target (not cached), so it
## reacts the first patrol cycle after a robbery and never goes stale.
const GUARD_BIAS_RADIUS := 300.0
const GUARDED_WANDER_RADIUS := 40.0
const GUARDED_DWELL_MIN_TICKS := 30   # 0.5 sim-second
const GUARDED_DWELL_MAX_TICKS := 150  # 2.5 sim-seconds

## Batch 10 (locked): "patrol high crime places" -- generalizes the guard
## tier above from "only ever a has_been_hit robbery" to any building with
## enough accumulated BuildingData.crime_heat (fed by ANY witnessed-and-
## recognized crime type, via CrimeSystem._bump_crime_heat). Same guarded
## radius/dwell constants as before; only the selection criterion changed,
## from "the first has_been_hit match" to "the hottest match in range."
const PATROL_BIAS_HEAT_THRESHOLD := 0.3

## Batch 10 (locked): "only raid if there's a bunch of evidence" -- a
## second, higher tier, considered only for a building with
## BuildingData.is_raidable == true (set at worldgen for ILLEGAL_FRONT/
## SAFEHOUSE lots -- reserved since Phase 0, never read until this batch).
## An ordinary residence or legit business still gets the guarded tier
## above like anything else, but never a full raid -- that stays reserved
## for the kind of location a raid narratively makes sense against.
## Crossing this threshold fires _conduct_raid as a one-time event (see its
## doc comment for why no separate cooldown tracking is needed) and tightens
## this tick's wander to RAID_WANDER_RADIUS/RAID_DWELL_*, tighter again than
## the guarded tier -- "more cops right on top of it" is half of Phil's
## explicit "both at once" choice for what a raid does.
const RAID_HEAT_THRESHOLD := 0.75
const RAID_WANDER_RADIUS := 15.0
const RAID_DWELL_MIN_TICKS := 10  # ~0.17 sim-second
const RAID_DWELL_MAX_TICKS := 60  # 1 sim-second

## The other half of "both at once": a raid on gang turf costs the owning
## gang real money and costs the player some of their standing with that
## gang -- a consequence for the gang's operation getting busted, not for
## the player personally. The player is never touched by a raid except
## through the ordinary witnessed+recognized path, same as always (see
## this file's top-of-doc evidence-gated constraint) -- a raid with no
## owning gang (an ordinary civilian hot spot) is just the heavier patrol
## above, nothing more.
const RAID_GANG_CASH_PENALTY_FRACTION := 0.5
const RAID_STANDING_PENALTY := 0.3

## How hard a raid relieves the raided building's own crime_heat -- strong
## but partial (not a hard reset to 0.0), and deliberately enough to drop
## it below even PATROL_BIAS_HEAT_THRESHOLD so the same building can't
## re-trigger a raid again the very next tick; it has to genuinely heat
## back up from fresh witnessed crime first.
const RAID_HEAT_RELIEF_FRACTION := 0.75

const BROADCAST_RADIUS := 400.0   # radio call reaches cops this far away
const ARREST_RADIUS := 2.0
## Batch 24: share of the player's dirty money seized on arrest.
const ARREST_SEIZE_FRACTION := 0.5
## If a cop never reaches the player within this many ticks of being
## alerted, give up and resume patrol rather than chasing forever on a
## stale lead.
const ALERT_TIMEOUT_TICKS := SimClock.TICKS_PER_SECOND * 90   # real distances: a 400 m run takes ~70 s

## WeakRef, not a direct World reference -- see NPCScheduleSystem's _world
## property doc for why (avoids a System<->World retain cycle).
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

## Per-cop patrol-wander state, owned here and passed into
## WanderBehavior.advance by reference every tick -- see WanderBehavior's
## doc comment for why it doesn't hold this state itself.
var _patrol_targets: Dictionary = {}      # StringName -> Vector2
var _patrol_dwell_until: Dictionary = {}  # StringName -> int

var _alerted: Dictionary = {}         # StringName -> bool
## Buildings hot enough to draw patrols, re-scanned every HOT_SCAN_TICKS: the
## real city has thousands of buildings, too many to scan per cop per tick.
const HOT_SCAN_TICKS := 15
var _hot_buildings: Array[BuildingData] = []
var _hot_scanned_tick := -1000000
var _alert_set_tick: Dictionary = {}  # StringName -> int

var _all_buildings: Array[BuildingData] = []
var _cops: Array[NPCData] = []
var beat := CopBeat.new()   # S3b: foot patrol along the streets round the station
var _cops_for := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.NPC

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	if tick - _hot_scanned_tick >= HOT_SCAN_TICKS:
		_collect_hot_buildings()
		_hot_scanned_tick = tick
	if _cops_for != entities.size():   # S1: six cops, not a walk over every person in the city each tick
		_cops_for = entities.size()
		_cops.clear()
		for entity in entities.values():
			var person: NPCData = entity.get_component(ComponentNames.NPC)
			if person.is_cop:
				_cops.append(person)
	for npc in _cops:
		if _alerted.get(npc.id, false):
			_advance_alert(npc, delta, tick)
		else:
			_advance_patrol(npc, delta, tick)

func _advance_patrol(npc: NPCData, delta: float, tick: int) -> void:
	var anchor := _depot_position(npc)
	var radius := PATROL_WANDER_RADIUS
	var dwell_min := PATROL_DWELL_MIN_TICKS
	var dwell_max := PATROL_DWELL_MAX_TICKS
	var hot_building := _find_hottest_nearby_building(anchor)
	if hot_building != null:
		anchor = hot_building.position
		radius = GUARDED_WANDER_RADIUS
		dwell_min = GUARDED_DWELL_MIN_TICKS
		dwell_max = GUARDED_DWELL_MAX_TICKS
		if hot_building.is_raidable and hot_building.crime_heat >= RAID_HEAT_THRESHOLD:
			_conduct_raid(hot_building)
			radius = RAID_WANDER_RADIUS
			dwell_min = RAID_DWELL_MIN_TICKS
			dwell_max = RAID_DWELL_MAX_TICKS
	var before := npc.position
	if hot_building == null:
		npc.position = beat.advance(npc, anchor, PATROL_SPEED, delta, tick)   # S3b: walk the beat
	else:
		beat.forget(npc.id)   # guarding a hot spot; the beat picks up again from the nearest corner
		npc.position = WanderBehavior.advance(
			npc.id, npc.position, anchor, radius, PATROL_SPEED,
			dwell_min, dwell_max, delta, tick,
			_patrol_targets, _patrol_dwell_until, ARRIVE_EPSILON
		)
	if npc.position != before:
		_world.reindex_position(npc.id)

## Batch 10 (locked): linear scan over all buildings -- same "fine at this
## phase's city scale" reasoning as the has_been_hit scan this replaces.
## Picks the HOTTEST building within range (not just the first match), so
## a cop actually biases toward the worst spot on their beat rather than
## whichever building happens to come first in iteration order.
func _collect_hot_buildings() -> void:
	_hot_buildings.clear()
	var all := _world.get_entities_with_component(ComponentNames.BUILDING)
	if _all_buildings.size() != all.size():   # S1: plain cached list; the scan runs 4x a second
		_all_buildings.clear()
		for entity in all.values():
			_all_buildings.append(entity.get_component(ComponentNames.BUILDING))
	for building in _all_buildings:
		if building.crime_heat >= PATROL_BIAS_HEAT_THRESHOLD:
			_hot_buildings.append(building)

func _find_hottest_nearby_building(depot_position: Vector2) -> BuildingData:
	var best: BuildingData = null
	for building in _hot_buildings:
		if building.crime_heat < PATROL_BIAS_HEAT_THRESHOLD:   # a raid this tick may have cooled it
			continue
		if building.position.distance_to(depot_position) > GUARD_BIAS_RADIUS:
			continue
		if best == null or building.crime_heat > best.crime_heat:
			best = building
	return best

## Batch 10 (locked): a one-time bust event, not a continuous effect --
## relieves the building's own heat hard enough (RAID_HEAT_RELIEF_FRACTION)
## that it drops below even the patrol-bias threshold immediately, which is
## what actually prevents this from re-firing every single HOT tick for as
## long as the condition would otherwise hold; no separate cooldown/
## already-raided tracking needed as a result. If two cops' beats overlap
## the same hot building in the same tick, only the first one processed
## actually raids it -- the second sees the already-relieved heat, same
## "first cop nearby reacts" shape as the rest of this file.
func _conduct_raid(building: BuildingData) -> void:
	building.crime_heat -= building.crime_heat * RAID_HEAT_RELIEF_FRACTION
	ProductionSystem.seize_stored(_world, building)  # batch 25: raided grow house loses its stash
	var gang_entity := CrimeSystem.find_territory_gang(_world, building.id)
	if gang_entity == null:
		return  # not gang turf -- the heavier patrol above is the whole consequence
	var gang: GangData = gang_entity.get_component(ComponentNames.GANG)
	gang.cash = maxi(0, gang.cash - int(round(gang.cash * RAID_GANG_CASH_PENALTY_FRACTION)))
	var player_entity := _get_player_entity()
	if player_entity == null:
		return
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	var standing: float = player_state.gang_standing.get(gang.id, 0.5)
	player_state.gang_standing[gang.id] = standing - standing * RAID_STANDING_PENALTY

## A cop's patrol origin -- PopulationSeeder gives every cop a
## home_building_id standing in for a precinct depot (see its _seed_cops
## doc comment). Degrades to the cop's own current position if that
## building somehow went missing, rather than crashing -- same defensive
## shape as NPCScheduleSystem._target_position's fallback.
func _depot_position(npc: NPCData) -> Vector2:
	if npc.home_building_id != &"" and _world.entities.has(npc.home_building_id):
		var depot: BuildingData = _world.entities[npc.home_building_id].get_component(ComponentNames.BUILDING)
		return depot.position
	return npc.position

func _advance_alert(npc: NPCData, delta: float, tick: int) -> void:
	var player_entity := _get_player_entity()
	if player_entity == null:
		_stand_down(npc.id)
		return
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	if player_state.law_tier == GanstoidEnums.LawTier.CLEAN:
		_stand_down(npc.id)  # no longer wanted -- nothing left to respond to
		return
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	if npc.position.distance_to(player_npc.position) <= ARREST_RADIUS:
		_arrest(player_npc, player_state)
		_stand_down(npc.id)
		return
	if tick - _alert_set_tick.get(npc.id, tick) > ALERT_TIMEOUT_TICKS:
		_stand_down(npc.id)
		return
	npc.position = WanderBehavior.step_toward(npc.position, player_npc.position, RESPONSE_SPEED, delta, ARRIVE_EPSILON, npc.id)
	_world.reindex_position(npc.id)

## Phase 1 "short jail stint" stub: no real jail scene/timer yet, just the
## two consequences that matter for the loop to feel real -- the heat
## clears, and you're set back at your own front door, not where you got
## caught. A fuller jail system (duration, crew/business running
## unattended) is explicitly Phase 3/4 scope per the roadmap.
func _arrest(player_npc: NPCData, player_state: PlayerStateData) -> void:
	player_state.law_tier = GanstoidEnums.LawTier.CLEAN
	DealSystem.cancel_handoff(_world, player_state)  # batch 11: getting busted mid-handoff kills the deal
	var seized := Wallet.seize_dirty(_world, ARREST_SEIZE_FRACTION)  # batch 24
	StreetTalk.say_key(_world, player_state, "arrested_seized" if seized > 0 else "arrested", seized)
	CrewLoyaltySystem.on_player_arrested(_world, player_state)  # batch 16
	if player_npc.home_building_id != &"" and _world.entities.has(player_npc.home_building_id):
		var home: BuildingData = _world.entities[player_npc.home_building_id].get_component(ComponentNames.BUILDING)
		player_npc.position = home.position
		_world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

func _stand_down(cop_id: StringName) -> void:
	_alerted.erase(cop_id)
	_alert_set_tick.erase(cop_id)

func _get_player_entity() -> Entity:
	var matches := _world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	for entity in matches.values():
		return entity
	return null

## Subscribed directly to World.event_bus by SystemRegistry -- see the same
## note on EscalationTickSystem.on_crime_witnessed. This is the ONLY entry
## point into _alerted -- see the locked "evidence-gated law response"
## constraint in this file's top doc comment and in the roadmap.
func on_crime_witnessed(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.CRIME_WITNESSED:
		return
	var crime_position: Vector2 = payload.get("position", Vector2.ZERO)
	var cops := _world.get_entities_with_component(ComponentNames.NPC)
	for entity in cops.values():
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if not npc.is_cop:
			continue
		if npc.position.distance_to(crime_position) <= BROADCAST_RADIUS:
			_alerted[npc.id] = true
			_alert_set_tick[npc.id] = _world.tick
			# Leaving patrol for an active alert -- drop stale wander state
			# so resuming patrol later (via _stand_down) picks a fresh drift
			# point instead of snapping back to wherever the alert found it.
			WanderBehavior.clear(npc.id, _patrol_targets, _patrol_dwell_until)
