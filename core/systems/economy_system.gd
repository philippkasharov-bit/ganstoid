## Phase 2 locked mechanics spec, made real: per-good price drift from
## demand/supply. (E2: tills no longer refill on their own; they fill from
## sales in EconomyFlow.) The backend core other Phase 2+ features (drug deals,
## odd jobs, robbery feedback) plug into -- this system doesn't process
## any transaction itself, it just keeps the numbers a transaction would
## read/write moving realistically on their own.
##
## required_component = BUILDING so World hands this the pre-indexed
## building set for the regen loop; the goods-price pass (World.economy_items
## is a plain Dictionary, not entities, so it can't be component-indexed)
## runs once per call regardless of that filter, not once per building.
##
## Batch 7 (locked): also decays EconomyItemData.player_market_reputation
## back toward its 0.5 baseline, same pass as demand/supply since all three
## live on the same per-good data and get touched by the same loop.
## DealSystem.buy/sell are what raise it (and what actually read it to
## price a trade) -- see that file's doc comment.
##
## Batch 8 (locked): also decays PlayerStateData.gang_standing/
## solo_standing back toward 0.5 -- same relationship-fades-if-untended
## shape as reputation, just living on the player entity instead of on a
## good, so it's a small separate lookup each warm tick rather than
## something the required_component=BUILDING filter already hands us.
class_name EconomySystem
extends SystemBase

## How far demand/supply move toward their 0.5 baseline each warm tick
## with no trades happening -- same decaying-scalar shape as
## RecognitionSystem.recognition_chance, not a hardcoded floor/ceiling.
const DEMAND_SUPPLY_DECAY := 0.05

## Batch 7 (locked): player_market_reputation's decay toward its 0.5
## baseline -- same shape as DEMAND_SUPPLY_DECAY, but deliberately slower.
## Demand/supply reflect the whole market's momentary mood and should
## snap back fast; reputation is meant to read as an established
## relationship with a good's market (DealSystem.buy/sell is what raises
## it), so it should fade out over a long dry spell, not evaporate the
## moment the player stops trading for a few ticks.
const REPUTATION_DECAY := 0.02

## Batch 8 (locked): same decay shape and rate as REPUTATION_DECAY for
## PlayerStateData.gang_standing/solo_standing -- a relationship with a
## gang or a solo contact is the same "fades if you stop tending it" idea
## as reputation with a good's market, so it gets the same cadence.
const RELATIONSHIP_DECAY := 0.02

## Batch 10 (locked): decays BuildingData.crime_heat back toward 0.0 (not
## 0.5 -- heat has no "neutral" baseline the way a relationship does, it
## just fades with a clean record). Slower than DEMAND_SUPPLY_DECAY but
## comparable to REPUTATION_DECAY/RELATIONSHIP_DECAY -- a place's
## reputation with cops is the same kind of slow-fading relationship, just
## negative instead of positive.
const CRIME_HEAT_DECAY := 0.015
const HEAT_FORGOTTEN := 0.0005

## Locked pricing formula (roadmap Phase 2 spec):
## current_price = base_price * clamp(1.0 + (demand - supply) * elasticity, min_mult, max_mult)
const PRICE_ELASTICITY := 0.8
const PRICE_MIN_MULT := 0.4
const PRICE_MAX_MULT := 2.5

var _buildings: Array[BuildingData] = []   # rebuilt when the number of buildings changes
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.WARM
	required_component = ComponentNames.BUILDING

func process_entities(entities: Dictionary, _delta: float, _tick: int) -> void:
	# S1: nearly every building is idle on any given tick (no heat, till full).
	# Walk a cached plain list and test that inline, instead of fetching the
	# component and making two calls for each of ~2,600 buildings six times a second.
	if _buildings.size() != entities.size():
		_buildings.clear()
		for entity in entities.values():
			_buildings.append(entity.get_component(ComponentNames.BUILDING))
	for building in _buildings:
		if building.crime_heat != 0.0:
			_decay_crime_heat(building)
	for item in _world.economy_items.values():
		_drift_price(item)
	_decay_relationships()

func _decay_relationships() -> void:
	var matches := _world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	for entity in matches.values():
		var state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
		for key in state.gang_standing.keys():
			state.gang_standing[key] += (0.5 - state.gang_standing[key]) * RELATIONSHIP_DECAY
		for key in state.solo_standing.keys():
			state.solo_standing[key] += (0.5 - state.solo_standing[key]) * RELATIONSHIP_DECAY
		return  # exactly one match, by construction -- see the doc comment above

## Batch 10 (locked): applies to every building
## regardless of daily_revenue -- a residence or illegal front with no
## legitimate revenue line can still be a hot corner, so crime_heat decays
## on all of them, not just revenue-earning ones.
func _decay_crime_heat(building: BuildingData) -> void:
	building.crime_heat += (0.0 - building.crime_heat) * CRIME_HEAT_DECAY
	if building.crime_heat < HEAT_FORGOTTEN:
		building.crime_heat = 0.0   # an exponential decay never reaches zero by itself

func _drift_price(item: EconomyItemData) -> void:
	item.demand += (0.5 - item.demand) * DEMAND_SUPPLY_DECAY
	item.supply += (0.5 - item.supply) * DEMAND_SUPPLY_DECAY
	item.player_market_reputation += (0.5 - item.player_market_reputation) * REPUTATION_DECAY
	var mult := clampf(1.0 + (item.demand - item.supply) * PRICE_ELASTICITY, PRICE_MIN_MULT, PRICE_MAX_MULT)
	item.current_price = int(round(item.base_price * mult))

## Called by whatever processes a completed deal (none exist yet this
## phase -- reserved entry point for the drug-deal/odd-job action, same
## role this file's doc comment describes: the backend core, not the
## action itself). buy_pressure/sell_drain follow the locked spec's
## diminishing-returns shape, not a flat add, so repeated big buys don't
## blow the price past PRICE_MAX_MULT in one swing.
static func record_trade(item: EconomyItemData, buy_pressure: float, sell_drain: float) -> void:
	item.demand += (1.0 - item.demand) * buy_pressure
	item.supply -= item.supply * sell_drain

## Called when the player robs a business (CrimeSystem, once a building-
## robbery action exists -- reserved for the same reason as record_trade).
## Drains cash_on_hand and flips has_been_hit, which is the data half of
## the locked "robbed corners get poorer/more guarded" feedback loop;
## CopAISystem/PopulationSeeder read has_been_hit for the "more guarded"
## half once that's built.
static func apply_robbery(building: BuildingData, amount_taken: int) -> void:
	building.cash_on_hand = maxi(0, building.cash_on_hand - amount_taken)
	building.has_been_hit = true
