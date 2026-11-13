## Phase 4 batch 23: business ownership -- the first piece of the legit
## path (roadmap sandbox rule: legit business is first-class, not a reskin).
##
## Buy (B) any legit, revenue-earning building that isn't gang turf and
## isn't already yours, for PRICE_DAYS x its daily_revenue. Ownership is
## BuildingData.owner_npc_id (reserved since Phase 0) set to the player id.
## Once per game day (SimClock.day_ticks) each owned shop hands you its till; the
## till refills over the day through EconomySystem's existing cash regen,
## so income tracks the shop's daily_revenue. Legit income: no crime, no
## witnesses, no crew cut.
##
## Your own shops are never robbery targets for you and never pay your
## muscle protection.
##
## Batch 24: shop income is CLEAN money, buying a shop needs clean money,
## and each day your shops also launder dirty money: up to their combined
## daily_revenue (a front can't plausibly wash more than it "earns"), at
## LAUNDER_FEE.
class_name BusinessSystem
extends SystemBase

const PRICE_DAYS := 10
## One game day = SimClock.day_ticks.
const LAUNDER_FEE := 0.2

var _last_payout_tick := 0
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.WARM
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick - _last_payout_tick < SimClock.day_ticks:
		return
	_last_payout_tick = tick
	for player in entities.values():
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		var paid := collect_all(_world)
		var washed: int = Wallet.launder(_world, laundering_capacity(_world), LAUNDER_FEE)["washed"]
		if washed > 0:
			StreetTalk.say_key(_world, state, "laundered", washed)
		elif paid > 0:
			StreetTalk.say_key(_world, state, "business_paid", paid)

## Batch 24: how much dirty money your shops can wash per day.
static func laundering_capacity(world: World) -> int:
	var total := 0
	for entity in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if owned_by_player(building):
			total += building.daily_revenue
	return total

static func owned_by_player(building: BuildingData) -> bool:
	return building.owner_npc_id == PlayerFactory.PLAYER_ENTITY_ID

static func price(building: BuildingData) -> int:
	return building.daily_revenue * PRICE_DAYS

## E2: a shop keeps this many days of its trade in the bank for wages and stock.
const RESERVE_DAYS := 3

## What an owned shop can hand you today: the till, and the bank above its reserve.
static func spare(building: BuildingData) -> int:
	return building.cash_on_hand + maxi(0, building.bank - building.daily_revenue * RESERVE_DAYS)

## Empties every owned shop's till, and its bank above the reserve, into the
## player's cash. Returns the total. (E2: the shop earns it from real sales.)
static func collect_all(world: World) -> int:
	var total := 0
	for building in all_buildings(world):
		if owned_by_player(building) and spare(building) > 0:
			total += spare(building)
			building.bank = mini(building.bank, building.daily_revenue * RESERVE_DAYS)
			building.cash_on_hand = 0
	Wallet.earn_clean(world, total)
	return total

## Owned legit shops (grow houses are counted by ProductionSystem).
static func count_owned(world: World) -> int:
	var n := 0
	for building in all_buildings(world):
		if owned_by_player(building) and building.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			n += 1
	return n

## PF1: every building as a plain list, kept between calls (2,400 component
## lookups an hour cost several ms; the set of buildings never changes in a run).
static var _all: Array[BuildingData] = []
static var _all_for := 0
static func all_buildings(world: World) -> Array[BuildingData]:
	var index := world.get_entities_with_component(ComponentNames.BUILDING)
	var stamp := world.get_instance_id() * 100003 + index.size()
	if stamp != _all_for:
		_all_for = stamp
		_all.clear()
		for entity in index.values():
			_all.append(entity.get_component(ComponentNames.BUILDING))
	return _all

static func buy(world: World, building_id: StringName) -> Dictionary:
	var entity: Entity = world.entities.get(building_id)
	if entity == null:
		return {"ok": false, "reason": "no_target"}
	var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
	var player_npc: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if building == null:
		return {"ok": false, "reason": "no_target"}
	if building.position.distance_to(player_npc.position) > CrimeSystem.INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if owned_by_player(building):
		return {"ok": false, "reason": "already_yours"}
	if building.building_type != GanstoidEnums.BuildingType.LEGIT_BUSINESS or building.daily_revenue <= 0 or CrimeSystem.find_territory_gang(world, building_id) != null:
		return {"ok": false, "reason": "not_for_sale"}
	var cost := price(building)
	if player_npc.cash < cost:
		return {"ok": false, "reason": "cant_afford_business"}
	if Wallet.clean(world) < cost:
		return {"ok": false, "reason": "need_clean_cash"}  # batch 24: dirty money can't buy a legit business
	Wallet.spend_clean(world, cost)
	building.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	return {"ok": true, "effect": "business_bought", "cost": cost}
