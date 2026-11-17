## LT1: what each kind of container holds. A container is filled when you
## first open it (a seeded roll, so a save reloads the same contents) and
## refills RESTOCK_DAYS after it was emptied, if the people there can pay for
## it (E3). Entries: [item, chance, min, max]. E3: no cash is rolled any more:
## the drawers of a home show that household's real cash, a register shows the
## shop's real till (CASH_IN).
class_name LootTables
extends RefCounted

const RESTOCK_DAYS := 3.0

## LT4: every piece of furniture is its own container with its own
## table, so a home is searched drawer by drawer, and what turns up feeds
## the businesses (cold medicine, seeds, plant food, drugs) or the pawn shop.
const TABLES := {
	"fridge": {"name": "Fridge", "secs": 2.0, "rolls": [[&"water", 0.6, 1, 3], [&"soda", 0.6, 1, 3], [&"burrito", 0.35, 1, 2], [&"liquor", 0.15, 1, 1], [&"weed", 0.04, 1, 3]]},
	"cabinet": {"name": "Kitchen cabinet", "secs": 3.0, "rolls": [[&"chips", 0.6, 1, 2], [&"coffee", 0.5, 1, 2], [&"knife", 0.3, 1, 1], [&"cash_tin", 0.06, 1, 1], [&"plant_food", 0.05, 1, 3], [&"liquor", 0.2, 1, 1]]},
	"medicine": {"name": "Medicine cabinet", "secs": 2.0, "rolls": [[&"bandage", 0.7, 1, 3], [&"cold_meds", 0.35, 1, 3], [&"pills", 0.2, 1, 3]]},
	"drawers": {"name": "Chest of drawers", "secs": 4.0, "rolls": [[&"watch", 0.15, 1, 1], [&"ring", 0.12, 1, 2], [&"gold_chain", 0.08, 1, 1], [&"walkman", 0.2, 1, 1], [&"pager", 0.12, 1, 1], [&"cigarettes", 0.2, 1, 2], [&"weed", 0.12, 1, 4], [&"pistol", 0.04, 1, 1], [&"ammo", 0.06, 1, 1]]},
	"wardrobe": {"name": "Wardrobe", "secs": 5.0, "rolls": [[&"leather_jacket", 0.2, 1, 1], [&"jordans", 0.2, 1, 1], [&"baseball_cards", 0.1, 1, 1], [&"cash_tin", 0.06, 1, 1], [&"bat", 0.1, 1, 1], [&"coke", 0.03, 1, 2], [&"seeds_mids", 0.03, 1, 4]]},
	"under_bed": {"name": "Under the bed", "secs": 3.0, "rolls": [[&"bat", 0.12, 1, 1], [&"pistol", 0.05, 1, 1], [&"ammo", 0.08, 1, 2], [&"cash_tin", 0.08, 1, 1], [&"game_console", 0.1, 1, 1], [&"heroin", 0.02, 1, 2]]},
	"shelf": {"name": "Shelf", "secs": 3.0, "rolls": [[&"boombox", 0.15, 1, 1], [&"cd_player", 0.15, 1, 1], [&"camcorder", 0.06, 1, 1], [&"baseball_cards", 0.1, 1, 1], [&"liquor", 0.15, 1, 1]]},
	"sofa": {"name": "Sofa cushions", "secs": 2.0, "rolls": [[&"cash", 0.4, 1, 12], [&"pager", 0.05, 1, 1], [&"weed", 0.06, 1, 1], [&"knife", 0.05, 1, 1]]},
	"tv_stand": {"name": "TV stand", "secs": 3.0, "rolls": [[&"tv", 0.35, 1, 1], [&"vcr", 0.4, 1, 1], [&"game_console", 0.15, 1, 1]]},
	"safe": {"name": "Wall safe", "secs": 9.0, "rolls": [[&"pearls", 0.3, 1, 1], [&"gold_chain", 0.4, 1, 2], [&"watch", 0.35, 1, 2], [&"ring", 0.3, 1, 3], [&"brick_phone", 0.2, 1, 1], [&"pistol_clean", 0.08, 1, 1], [&"coke", 0.1, 2, 5]]},
	"register": {"name": "Cash register", "secs": 2.0, "rolls": []},
	"stockroom": {"name": "Stockroom shelves", "secs": 5.0, "rolls": [[&"water", 0.8, 2, 4], [&"soda", 0.8, 2, 4], [&"chips", 0.8, 2, 5], [&"bandage", 0.4, 1, 3], [&"cold_meds", 0.3, 2, 6], [&"cigarettes", 0.5, 1, 4], [&"liquor", 0.4, 1, 3]]},
	"pockets": {"name": "Pockets", "secs": 2.5, "rolls": [[&"chips", 0.2, 1, 1], [&"soda", 0.15, 1, 1], [&"bandage", 0.12, 1, 1], [&"pills", 0.08, 1, 1], [&"weed", 0.08, 1, 2], [&"knife", 0.08, 1, 1], [&"watch", 0.1, 1, 1], [&"pager", 0.1, 1, 1], [&"walkman", 0.08, 1, 1], [&"gold_chain", 0.04, 1, 1], [&"cigarettes", 0.15, 1, 1]]},   # LT3
	"pockets_cop": {"name": "Pockets", "secs": 2.5, "rolls": [[&"pistol", 0.5, 1, 1], [&"ammo", 0.7, 1, 2], [&"bandage", 0.4, 1, 2], [&"watch", 0.2, 1, 1]]},
	"pockets_dealer": {"name": "Pockets", "secs": 2.5, "rolls": [[&"weed", 0.9, 2, 6], [&"pills", 0.4, 1, 3], [&"coke", 0.2, 1, 3], [&"knife", 0.35, 1, 1], [&"pistol", 0.1, 1, 1], [&"gold_chain", 0.3, 1, 1], [&"pager", 0.6, 1, 1], [&"seeds_kush", 0.08, 1, 3]]},
	"glovebox": {"name": "Glovebox", "secs": 0.0, "rolls": [[&"cash", 0.6, 2, 40], [&"knife", 0.1, 1, 1], [&"ammo", 0.05, 1, 1], [&"chips", 0.3, 1, 1], [&"cigarettes", 0.2, 1, 1], [&"pager", 0.05, 1, 1]]},
}
## Furniture a home has (each one rolled per piece in the layout).
const HOME := ["fridge", "cabinet", "medicine", "drawers", "wardrobe", "under_bed", "shelf", "sofa", "tv_stand"]
const SAFE_WEALTH := 0.6   # homes on blocks this well off have a wall safe

## E3: the container that holds a building's own money (BuildingData.cash_on_hand).
const CASH_IN := ["drawers", "register"]

## What a roll is worth (what the household or shop pays to stock it again).
static func value(items: Dictionary) -> int:
	var total := 0
	for id in items:
		total += int(ItemCatalog.item(id).get("price", 0)) * int(items[id])
	return total

## Which containers a building of this kind has.
static func containers_for(building: BuildingData, world: World = null) -> Array:
	match building.building_type:
		GanstoidEnums.BuildingType.RESIDENCE:
			return HOME + (["safe"] if world != null and float(BlockEconomyData.block_at(world, building.position).get("wealth", 0.0)) >= SAFE_WEALTH else [])
		GanstoidEnums.BuildingType.SAFEHOUSE:
			return ["fridge", "cabinet", "drawers", "under_bed"]
	return ["register", "stockroom"]

## LT4: how long a search of it takes (seconds), quicker with theft skill.
static func search_secs(kind: String, theft_level: int) -> float:
	return float(TABLES.get(kind, {}).get("secs", 3.0)) * (1.0 - 0.04 * theft_level)

## A fresh roll of one container: {item: count}.
static func roll(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for r in TABLES[kind]["rolls"]:
		if rng.randf() < r[1]:
			out[r[0]] = rng.randi_range(r[2], r[3])
	return out
