## Fixed catalog of tradeable goods -- not generated, not an entity. World
## holds exactly one EconomyItemData per good_id in World.economy_items,
## seeded once at new-game start. Kept separate from CityGenerator/
## PopulationSeeder (which produce per-city, per-seed content) because
## goods are a fixed game-design list, same for every city/seed.
##
## Both goods start is_illegal=true -- the only trade this phase's dealer
## NPCs will offer. Legal goods (what a LEGIT_BUSINESS actually sells) are
## Phase 2's next pass, once a buy/sell UI exists to make them meaningful.
class_name GoodsCatalog
extends RefCounted

const GOODS := [
	{"good_id": &"weed", "display_name": "Weed", "base_price": 20, "is_illegal": true},
	{"good_id": &"pills", "display_name": "Pills", "base_price": 40, "is_illegal": true},
]

static func seed_goods(world: World) -> void:
	for entry in GOODS:
		var item := EconomyItemData.new()
		item.good_id = entry["good_id"]
		item.display_name = entry["display_name"]
		item.base_price = entry["base_price"]
		item.current_price = entry["base_price"]
		item.is_illegal = entry["is_illegal"]
		world.economy_items[item.good_id] = item
