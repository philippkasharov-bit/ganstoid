## Phase 4 batch 25: growing your own product. Buy a safehouse (B, clean
## money, GROW_HOUSE_PRICE) and it becomes a grow house: once per game day
## it costs GROW_DAILY_COST in supplies (dirty money is fine) and adds
## GROW_YIELD weed to its store, up to STORAGE_CAP. Can't pay, no harvest
## that day. Press Enter at your grow house to pick up the harvest.
##
## Risk: every harvest is a chance for the neighbours to notice -- a daily
## witness roll at the house (reports_player = false: it heats the house,
## never your personal heat). Safehouses are is_raidable, so a house that
## gets hot enough gets raided (CopAISystem._conduct_raid), and a raid
## seizes everything stored there.
class_name ProductionSystem
extends SystemBase

const GROW_HOUSE_PRICE := 800
const GROW_DAILY_COST := 40
const GROW_YIELD := 6
const STORAGE_CAP := 30
const GOOD_ID := &"weed"

var _last_harvest_tick := 0
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.WARM
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick - _last_harvest_tick < BusinessSystem.DAY_TICKS:
		return
	_last_harvest_tick = tick
	grow_all(_world)

static func is_grow_house(building: BuildingData) -> bool:
	return building.building_type == GanstoidEnums.BuildingType.SAFEHOUSE and BusinessSystem.owned_by_player(building)

## One day's growing across every grow house. Returns units grown.
static func grow_all(world: World) -> int:
	var grown := 0
	var player_npc: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	for entity in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if not is_grow_house(building) or building.stored_product >= STORAGE_CAP:
			continue
		if player_npc.cash < GROW_DAILY_COST:
			continue  # can't pay for supplies -- no harvest today
		Wallet.spend(world, GROW_DAILY_COST)
		var added := mini(GROW_YIELD, STORAGE_CAP - building.stored_product)
		building.stored_product += added
		grown += added
		CrimeSystem.broadcast_witnesses(world, building.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED], false)
	return grown

static func count_grow_houses(world: World) -> int:
	var n := 0
	for entity in world.get_entities_with_component(ComponentNames.BUILDING).values():
		if is_grow_house(entity.get_component(ComponentNames.BUILDING)):
			n += 1
	return n

static func buy(world: World, building_id: StringName) -> Dictionary:
	var building: BuildingData = world.entities[building_id].get_component(ComponentNames.BUILDING)
	var player_npc: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if building.position.distance_to(player_npc.position) > CrimeSystem.INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if BusinessSystem.owned_by_player(building):
		return {"ok": false, "reason": "already_yours"}
	if CrimeSystem.find_territory_gang(world, building_id) != null:
		return {"ok": false, "reason": "not_for_sale"}
	if player_npc.cash < GROW_HOUSE_PRICE:
		return {"ok": false, "reason": "cant_afford_business"}
	if Wallet.clean(world) < GROW_HOUSE_PRICE:
		return {"ok": false, "reason": "need_clean_cash"}
	Wallet.spend_clean(world, GROW_HOUSE_PRICE)
	building.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	return {"ok": true, "effect": "grow_house_bought", "cost": GROW_HOUSE_PRICE}

## Enter at your own grow house: take everything stored into your stash.
static func collect(world: World, building_id: StringName) -> Dictionary:
	var building: BuildingData = world.entities[building_id].get_component(ComponentNames.BUILDING)
	var state: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	if building.stored_product <= 0:
		return {"ok": false, "reason": "nothing_grown"}
	var qty := building.stored_product
	building.stored_product = 0
	state.inventory[GOOD_ID] = state.inventory.get(GOOD_ID, 0) + qty
	return {"ok": true, "effect": "harvest_collected", "quantity": qty}

## Raid hook (CopAISystem._conduct_raid): cops take whatever is stored.
static func seize_stored(world: World, building: BuildingData) -> int:
	if not is_grow_house(building) or building.stored_product <= 0:
		return 0
	var seized := building.stored_product
	building.stored_product = 0
	StreetTalk.say_key(world, world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE), "grow_house_raided", seized)
	return seized
