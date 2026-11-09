## Phase 3 batch 15: recruiting civilians into the player's crew, and keeping
## recruited crew loosely trailing the player until real task assignment
## exists (Crew D). Recruiting is not a crime -- no witness broadcast, so it
## never touches the evidence-gated law chain.
##
## Willingness reuses data that already exists instead of a new stat: no
## job, living out on the city's EDGE zone, and having seen the player work
## (RecognitionSystem.recognition_chance) all make someone easier to pull in.
## A refusal is final for that NPC (NPCData.recruit_refused) so the pitch
## can't be re-rolled forever.
class_name CrewSystem
extends SystemBase

const MAX_CREW := 5
const RECRUIT_COST := 50
const BASE_WILLINGNESS := 0.2
const UNEMPLOYED_BONUS := 0.25
const EDGE_ZONE_BONUS := 0.15
const SEEN_YOU_WORK_WEIGHT := 0.35
const MAX_WILLINGNESS := 0.9

## Trailing behavior: loiter near the player via the shared WanderBehavior.
const FOLLOW_RADIUS := 4.0
const FOLLOW_SPEED := SimUnits.JOG
const FOLLOW_DWELL_MIN_TICKS := 30
const FOLLOW_DWELL_MAX_TICKS := 120
const ARRIVE_EPSILON := 2.0

## Batch 17 -- LOOKOUT. Posted on a spot (toggle_post), the lookout stays
## there and covers anything within LOOKOUT_RADIUS: each witness who would
## have recognized you gets waved off LOOKOUT_SUPPRESS_CHANCE of the time.
## Only ever REDUCES recognition -- never adds a law trigger. Lookouts
## don't stack; covered is covered.
const LOOKOUT_RADIUS := 80.0
const LOOKOUT_SUPPRESS_CHANCE := 0.5
const LOOKOUT_LOITER_RADIUS := 6.0
const LOOKOUT_SPEED := SimUnits.WALK

## Batch 20 -- DRIVER. Rides with you (glued to your position, no wander)
## and speeds you up: DRIVER_SPEED_MULT normally, GETAWAY_SPEED_MULT while
## you have heat. Walking (90) loses a foot race to a responding cop (110);
## with a driver you're at 126, and 144 on a getaway -- you can outrun them.
## Stand-in for real vehicles (later in the plan), not a replacement.
const DRIVER_SPEED_MULT := 1.4
const GETAWAY_SPEED_MULT := 1.6
const DRIVER_OFFSET := Vector2(-10, 6)

var _follow_targets: Dictionary = {}
var _follow_dwell_until: Dictionary = {}
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

## entities is the single player entity (required_component = PLAYER_STATE);
## the crew themselves are walked via PlayerStateData.crew_ids (<= MAX_CREW).
func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	for player in entities.values():
		var anchor: Vector2 = player.get_component(ComponentNames.NPC).position
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		for crew_id in state.crew_ids:
			_trail(crew_id, anchor, delta, tick)

func _trail(crew_id: StringName, anchor: Vector2, delta: float, tick: int) -> void:
	var entity: Entity = _world.entities.get(crew_id)
	if entity == null:
		return
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if npc.crew_role == GanstoidEnums.CrewRole.DRIVER:
		npc.position = anchor + DRIVER_OFFSET  # riding with you
		_world.reindex_position(npc.id)
		return
	var posted := npc.crew_role != GanstoidEnums.CrewRole.UNASSIGNED
	npc.position = WanderBehavior.advance(
		npc.id, npc.position, npc.post_position if posted else anchor,
		LOOKOUT_LOITER_RADIUS if posted else FOLLOW_RADIUS,
		LOOKOUT_SPEED if posted else FOLLOW_SPEED,
		FOLLOW_DWELL_MIN_TICKS, FOLLOW_DWELL_MAX_TICKS, delta, tick,
		_follow_targets, _follow_dwell_until, ARRIVE_EPSILON
	)
	_world.reindex_position(npc.id)

static func willingness(world: World, npc: NPCData) -> float:
	var w := BASE_WILLINGNESS
	if npc.work_building_id == &"":
		w += UNEMPLOYED_BONUS
	var home: Entity = world.entities.get(npc.home_building_id)
	if home != null and home.get_component(ComponentNames.BUILDING).zone == GanstoidEnums.CityZone.EDGE:
		w += EDGE_ZONE_BONUS
	w += npc.recognition_chance * SEEN_YOU_WORK_WEIGHT
	return minf(w, MAX_WILLINGNESS)

static func recruit(world: World, npc_id: StringName) -> Dictionary:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var target: Entity = world.entities.get(npc_id)
	if player == null or target == null:
		return {"ok": false, "reason": "no_target"}
	var player_npc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	var npc: NPCData = target.get_component(ComponentNames.NPC)
	if npc == null or npc.is_cop or npc.is_dealer or npc.is_crew:
		return {"ok": false, "reason": "not_recruitable"}
	if npc.position.distance_to(player_npc.position) > CrimeSystem.INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if npc.recruit_refused:
		return {"ok": false, "reason": "already_refused"}
	if state.crew_ids.size() >= MAX_CREW:
		return {"ok": false, "reason": "crew_full"}
	if player_npc.cash < RECRUIT_COST:
		return {"ok": false, "reason": "cant_afford"}
	if world.runtime_rng.randf() >= willingness(world, npc):
		npc.recruit_refused = true
		return {"ok": false, "reason": "recruit_refused"}
	Wallet.spend(world, RECRUIT_COST)  # batch 24
	npc.is_crew = true
	npc.crew_role = GanstoidEnums.CrewRole.UNASSIGNED
	state.crew_ids.append(npc_id)
	return {"ok": true, "effect": "recruit", "cost": RECRUIT_COST}

## Batch 17: posts a following crew member as a lookout where they stand,
## or recalls a posted lookout back to following you.
static func toggle_post(world: World, crew_id: StringName) -> Dictionary:
	var entity: Entity = world.entities.get(crew_id)
	if entity == null:
		return {"ok": false, "reason": "no_target"}
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if not npc.is_crew:
		return {"ok": false, "reason": "not_crew"}
	if npc.crew_role != GanstoidEnums.CrewRole.UNASSIGNED and npc.crew_role != GanstoidEnums.CrewRole.LOOKOUT:
		return {"ok": false, "reason": "crew_busy"}  # pull them off their job first (G / M)
	if npc.crew_role == GanstoidEnums.CrewRole.LOOKOUT:
		npc.crew_role = GanstoidEnums.CrewRole.UNASSIGNED
		return {"ok": true, "effect": "recalled"}
	npc.crew_role = GanstoidEnums.CrewRole.LOOKOUT
	npc.post_position = npc.position
	return {"ok": true, "effect": "posted"}

static func lookout_covers(world: World, position: Vector2) -> bool:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player == null:
		return false
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	for crew_id in state.crew_ids:
		var entity: Entity = world.entities.get(crew_id)
		if entity == null:
			continue
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc.crew_role == GanstoidEnums.CrewRole.LOOKOUT and npc.position.distance_to(position) <= LOOKOUT_RADIUS:
			return true
	return false

static func count_lookouts(world: World, state: PlayerStateData) -> int:
	return count_role(world, state, GanstoidEnums.CrewRole.LOOKOUT)

static func count_role(world: World, state: PlayerStateData, role: GanstoidEnums.CrewRole) -> int:
	var n := 0
	for crew_id in state.crew_ids:
		var entity: Entity = world.entities.get(crew_id)
		if entity != null and entity.get_component(ComponentNames.NPC).crew_role == role:
			n += 1
	return n

## Batch 20: V near a crew member makes them your driver, or lets them out.
static func toggle_driver(world: World, crew_id: StringName) -> Dictionary:
	var entity: Entity = world.entities.get(crew_id)
	if entity == null:
		return {"ok": false, "reason": "no_target"}
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if not npc.is_crew:
		return {"ok": false, "reason": "not_crew"}
	if npc.crew_role == GanstoidEnums.CrewRole.DRIVER:
		npc.crew_role = GanstoidEnums.CrewRole.UNASSIGNED
		return {"ok": true, "effect": "driver_dismissed"}
	if npc.crew_role != GanstoidEnums.CrewRole.UNASSIGNED:
		return {"ok": false, "reason": "crew_busy"}
	npc.crew_role = GanstoidEnums.CrewRole.DRIVER
	return {"ok": true, "effect": "driver_assigned"}

## Batch 20: movement multiplier PlayerInputSystem applies. Drivers don't stack.
static func player_speed_multiplier(world: World, state: PlayerStateData) -> float:
	if count_role(world, state, GanstoidEnums.CrewRole.DRIVER) == 0:
		return 1.0
	if state.law_tier != GanstoidEnums.LawTier.CLEAN:
		return GETAWAY_SPEED_MULT
	return DRIVER_SPEED_MULT
