## LT1: what each kind of container holds. A container is filled when you
## first open it (a seeded roll, so a save reloads the same contents) and
## refills RESTOCK_DAYS after it was emptied. Entries: [item, chance, min, max].
## "cash" is money, not a bag item.
class_name LootTables
extends RefCounted

const RESTOCK_DAYS := 3.0

const TABLES := {
	"kitchen": {"name": "Kitchen cupboards", "rolls": [[&"water", 0.7, 1, 2], [&"soda", 0.5, 1, 2], [&"chips", 0.6, 1, 2], [&"burrito", 0.35, 1, 1], [&"coffee", 0.4, 1, 1], [&"knife", 0.25, 1, 1]]},
	"bathroom": {"name": "Bathroom cabinet", "rolls": [[&"bandage", 0.75, 1, 3], [&"pills", 0.3, 1, 2]]},
	"bedroom": {"name": "Bedroom drawers", "rolls": [[&"cash", 0.9, 10, 120], [&"weed", 0.2, 1, 4], [&"knife", 0.15, 1, 1], [&"pistol", 0.06, 1, 1], [&"ammo", 0.1, 1, 1]]},
	"register": {"name": "Cash register", "rolls": [[&"cash", 1.0, 60, 260]]},
	"stockroom": {"name": "Stockroom shelves", "rolls": [[&"water", 0.8, 2, 4], [&"soda", 0.8, 2, 4], [&"chips", 0.8, 2, 5], [&"bandage", 0.4, 1, 3]]},
	"glovebox": {"name": "Glovebox", "rolls": [[&"cash", 0.6, 2, 40], [&"knife", 0.1, 1, 1], [&"ammo", 0.05, 1, 1], [&"chips", 0.3, 1, 1]]},
}

## Which containers a building of this kind has.
static func containers_for(building: BuildingData) -> Array:
	match building.building_type:
		GanstoidEnums.BuildingType.RESIDENCE:
			return ["kitchen", "bathroom", "bedroom"]
		GanstoidEnums.BuildingType.SAFEHOUSE:
			return ["kitchen", "bedroom"]
	return ["register", "stockroom"]

## A fresh roll of one container: {item: count}.
static func roll(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for r in TABLES[kind]["rolls"]:
		if rng.randf() < r[1]:
			out[r[0]] = rng.randi_range(r[2], r[3])
	return out
