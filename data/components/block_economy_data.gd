## E1: money by block (the 120 m turf cells). Each block has how well off it
## is, the public budget its shops' taxes build up (what pays its police and
## upkeep), how well funded its police are, and how strong the street (black)
## market is. A rich block: good wages, fat tills, well paid cops, a weak black
## market. A poor block: the reverse. Pure data; EconomyFlow (E2) moves money.
class_name BlockEconomyData
extends Resource

const ENTITY_ID := &"block_economy"

## Vector2i cell -> {"wealth": 0..1, "budget": $, "police": 0..1, "black": 0..1}
@export var blocks: Dictionary = {}
@export var last_day: Dictionary = {}
@export var news: Array = []            # E5: [{tick, text, at}], newest last, for the news feed (capped)
const NEWS_KEEP := 40

## E5: something happened on the street worth talking about.
func report(tick: int, text: String, at: Vector2) -> void:
	news.append({"tick": tick, "text": text, "at": at})
	while news.size() > NEWS_KEEP:
		news.pop_front()   # E2: yesterday's ledger {inflow, outflow, sales, wages, tax}

static func of(world: World) -> BlockEconomyData:
	var e: Entity = world.entities.get(ENTITY_ID)
	return e.get_component(ComponentNames.BLOCK_ECONOMY) if e != null else null

## The block a point is on (an empty middling block if the map has none there).
static func block_at(world: World, p: Vector2) -> Dictionary:
	var data := of(world)
	if data == null:
		return {"wealth": 0.5, "budget": 0, "police": 0.5, "black": 0.5}
	return data.blocks.get(TerritoryData.cell_of(p), {"wealth": 0.5, "budget": 0, "police": 0.5, "black": 0.5})

## One word for how a block is doing (for the player's eye).
static func describe(wealth: float) -> String:
	return "Rich" if wealth >= 0.7 else ("Comfortable" if wealth >= 0.5 else ("Getting by" if wealth >= 0.3 else "Poor"))
