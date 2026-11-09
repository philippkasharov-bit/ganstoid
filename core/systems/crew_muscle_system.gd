## Phase 3 batch 19: crew MUSCLE role. Post a crew member (M) and they lean
## on every legit business within MUSCLE_RADIUS for protection money:
## PROTECTION_FRACTION of the shop's daily_revenue, capped by what's in the
## register, at most once per PROTECTION_COOLDOWN_TICKS (one game day) per
## shop. They hold the money until you collect (M again), minus their cut.
##
## Payout-source integrity: the money comes out of the shop's own
## cash_on_hand, which EconomySystem regenerates -- no money from nowhere.
## Gang turf is off-limits (shaking down a gang's corner is a Beef Ladder
## matter, not built yet).
##
## Risk: each shakedown is a witnessable EXTORTION at THEIR spot -- a
## recognition heats that block but never raises YOUR law tier
## (reports_player = false), same rule as the crew dealer.
class_name CrewMuscleSystem
extends SystemBase

const MUSCLE_RADIUS := 120.0
const PROTECTION_FRACTION := 0.1
const PROTECTION_COOLDOWN_TICKS := 1800

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.WARM
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, _tick: int) -> void:
	for player in entities.values():
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		for crew_id in state.crew_ids:
			var entity: Entity = _world.entities.get(crew_id)
			if entity == null:
				continue
			var npc: NPCData = entity.get_component(ComponentNames.NPC)
			if npc.crew_role == GanstoidEnums.CrewRole.MUSCLE:
				shake_down(_world, npc)

## Collects from every eligible shop in range this tick. Returns the total.
static func shake_down(world: World, muscle: NPCData) -> int:
	var total := 0
	for id in world.spatial_index.query_nearby(muscle.position):
		var entity: Entity = world.entities.get(id)
		if entity == null:
			continue
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building == null or not _eligible(world, id, building, muscle.position):
			continue
		var take := mini(building.cash_on_hand, ceili(building.daily_revenue * PROTECTION_FRACTION))
		building.cash_on_hand -= take
		building.protection_paid_tick = world.tick
		muscle.crew_earnings += take
		total += take
		CrimeSystem.broadcast_witnesses(world, building.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.EXTORTION], false)
	return total

static func _eligible(world: World, id: StringName, building: BuildingData, at: Vector2) -> bool:
	if building.daily_revenue <= 0 or building.cash_on_hand <= 0:
		return false
	if BusinessSystem.owned_by_player(building):
		return false  # batch 23: your own shops don't pay you protection
	if building.position.distance_to(at) > MUSCLE_RADIUS:
		return false
	if world.tick - building.protection_paid_tick < PROTECTION_COOLDOWN_TICKS:
		return false
	return CrimeSystem.find_territory_gang(world, id) == null

## M near a crew member: post them as muscle, or collect and bring them back.
static func toggle(world: World, crew_id: StringName) -> Dictionary:
	var entity: Entity = world.entities.get(crew_id)
	if entity == null:
		return {"ok": false, "reason": "no_target"}
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if not npc.is_crew:
		return {"ok": false, "reason": "not_crew"}
	if npc.crew_role == GanstoidEnums.CrewRole.MUSCLE:
		var payout := CrewLoyaltySystem.pay_out_earnings(world, npc)
		npc.crew_role = GanstoidEnums.CrewRole.UNASSIGNED
		return {"ok": true, "effect": "muscle_collected", "payout": payout}
	if npc.crew_role != GanstoidEnums.CrewRole.UNASSIGNED and npc.crew_role != GanstoidEnums.CrewRole.LOOKOUT:
		return {"ok": false, "reason": "crew_busy"}
	npc.crew_role = GanstoidEnums.CrewRole.MUSCLE
	npc.post_position = npc.position
	return {"ok": true, "effect": "muscle_posted"}
