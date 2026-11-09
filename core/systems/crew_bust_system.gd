## Phase 3 batch 21: crew getting busted. A crew member working a corner
## (DEALER or MUSCLE -- the roles that commit crimes while posted) gets
## arrested when a cop comes within BUST_RADIUS of them AND their corner is
## hot: some building within CrimeSystem.CRIME_HEAT_RADIUS of their post has
## crime_heat at or above CopAISystem.PATROL_BIAS_HEAT_THRESHOLD.
##
## Evidence-gate fit: crime_heat only ever rises from witnessed+recognized
## crimes, so a bust needs real evidence on that corner -- a cop strolling
## past a quiet corner never busts anyone. It's the same heat that already
## pulls patrols toward the spot (batch 10), so working one corner too long
## invites the bust naturally. Lookouts and drivers commit nothing and are
## never busted. Busts never touch the player's law tier.
##
## Consequence: that crew member is gone for good (out of the crew, won't
## rejoin), and whatever product and cash they were holding is seized.
class_name CrewBustSystem
extends SystemBase

const BUST_RADIUS := 25.0

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
		for crew_id in state.crew_ids.duplicate():  # bust() mutates crew_ids
			var entity: Entity = _world.entities.get(crew_id)
			if entity == null:
				continue
			var npc: NPCData = entity.get_component(ComponentNames.NPC)
			if _exposed(npc) and corner_is_hot(_world, npc.post_position) and _cop_nearby(_world, npc.position):
				bust(_world, state, crew_id)

static func _exposed(npc: NPCData) -> bool:
	return npc.crew_role == GanstoidEnums.CrewRole.DEALER or npc.crew_role == GanstoidEnums.CrewRole.MUSCLE

static func corner_is_hot(world: World, at: Vector2) -> bool:
	for id in world.spatial_index.query_nearby(at):
		var entity: Entity = world.entities.get(id)
		if entity == null:
			continue
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building != null and building.position.distance_to(at) <= CrimeSystem.CRIME_HEAT_RADIUS and building.crime_heat >= CopAISystem.PATROL_BIAS_HEAT_THRESHOLD:
			return true
	return false

static func _cop_nearby(world: World, at: Vector2) -> bool:
	for id in world.spatial_index.query_nearby(at):
		var entity: Entity = world.entities.get(id)
		if entity == null:
			continue
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_cop and npc.position.distance_to(at) <= BUST_RADIUS:
			return true
	return false

static func bust(world: World, state: PlayerStateData, crew_id: StringName) -> void:
	state.crew_ids.erase(crew_id)
	var entity: Entity = world.entities.get(crew_id)
	if entity != null:
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		npc.is_crew = false
		npc.crew_role = GanstoidEnums.CrewRole.UNASSIGNED
		npc.recruit_refused = true
		npc.crew_stash = 0
		npc.crew_earnings = 0
	StreetTalk.say_key(world, state, "crew_busted")
