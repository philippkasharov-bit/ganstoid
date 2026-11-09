## Phase 3 batch 18: crew DEALER role. Post a crew member on a corner (G)
## with up to CONSIGNMENT units of your weed; while posted they sell to any
## civilian who wanders within CUSTOMER_RADIUS, a unit at a time, at the
## street price. Press G near them again to collect: unsold stash comes
## back, sales cash comes to you minus their cut (same CREW_CUT_FRACTION as
## every other score, and it raises their loyalty the same way).
##
## Risks, mirroring what the player faces when dealing:
##   - customers stiff them CUSTOMER_STIFF_CHANCE of the time (unit gone,
##     no cash),
##   - every sale is witnessable at THEIR corner -- a recognition heats that
##     corner (tighter patrols, eventual raids) but never raises YOUR law
##     tier, since you weren't there (broadcast_witnesses reports_player =
##     false). Crew getting busted on the corner is Crew E's job.
class_name CrewDealerSystem
extends SystemBase

const CONSIGNMENT := 5
const GOOD_ID := &"weed"
const CUSTOMER_RADIUS := 30.0
## Per warm tick (6/sec) with a customer in range: ~one sale per 5 sec.
const SALE_CHANCE := 1.0 / 30.0
const CUSTOMER_STIFF_CHANCE := 0.15
const SALE_SUPPLY_BUMP := 0.05

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
			if npc.crew_role == GanstoidEnums.CrewRole.DEALER and npc.crew_stash > 0:
				_try_sale(npc)

func _try_sale(dealer: NPCData) -> void:
	if not has_customer(_world, dealer.position) or _world.runtime_rng.randf() >= SALE_CHANCE:
		return
	dealer.crew_stash -= 1
	CrimeSystem.broadcast_witnesses(_world, dealer.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED], false)
	if _world.runtime_rng.randf() < CUSTOMER_STIFF_CHANCE:
		return
	var item: EconomyItemData = _world.economy_items[GOOD_ID]
	dealer.crew_earnings += item.current_price
	item.supply += (1.0 - item.supply) * SALE_SUPPLY_BUMP

static func has_customer(world: World, position: Vector2) -> bool:
	for id in world.spatial_index.query_nearby(position):
		var entity: Entity = world.entities.get(id)
		if entity == null or entity.has_component(ComponentNames.PLAYER_STATE):
			continue
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc == null or npc.is_crew or npc.is_cop or npc.is_dealer:
			continue
		if npc.position.distance_to(position) <= CUSTOMER_RADIUS:
			return true
	return false

## G near a crew member: hand them a consignment and post them, or collect
## from a posted dealer and bring them back.
static func toggle(world: World, crew_id: StringName) -> Dictionary:
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	var entity: Entity = world.entities.get(crew_id)
	if entity == null:
		return {"ok": false, "reason": "no_target"}
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if not npc.is_crew:
		return {"ok": false, "reason": "not_crew"}
	if npc.crew_role == GanstoidEnums.CrewRole.DEALER:
		return _collect(world, state, npc)
	if npc.crew_role != GanstoidEnums.CrewRole.UNASSIGNED and npc.crew_role != GanstoidEnums.CrewRole.LOOKOUT:
		return {"ok": false, "reason": "crew_busy"}
	var held: int = state.inventory.get(GOOD_ID, 0)
	if held <= 0:
		return {"ok": false, "reason": "nothing_to_sell"}
	var handed := mini(held, CONSIGNMENT)
	state.inventory[GOOD_ID] = held - handed
	npc.crew_stash += handed
	npc.crew_role = GanstoidEnums.CrewRole.DEALER
	npc.post_position = npc.position
	return {"ok": true, "effect": "dealer_posted"}

static func _collect(world: World, state: PlayerStateData, npc: NPCData) -> Dictionary:
	var payout := CrewLoyaltySystem.pay_out_earnings(world, npc)
	state.inventory[GOOD_ID] = state.inventory.get(GOOD_ID, 0) + npc.crew_stash
	npc.crew_stash = 0
	npc.crew_role = GanstoidEnums.CrewRole.UNASSIGNED
	return {"ok": true, "effect": "dealer_collected", "payout": payout}
