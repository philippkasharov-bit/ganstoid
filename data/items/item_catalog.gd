## Items (G1): every thing the player can carry, as one data table. Pure data:
## systems read it; nothing here changes state.
##   kind     food | drink | medical | weapon | ammo
##   price    dollars at a counter (black-market goods: at a dealer)
##   sold_at  shop | workshop | dealer   (who has it on the shelf)
##   hunger / thirst / tired  how much one use restores (0..1 of the need)
##   heal     health one use gives back; stops bleeding
##   weapon   key into CombatSystem.WEAPONS
##   rounds   pistol rounds in one box
class_name ItemCatalog
extends RefCounted

const ITEMS := {
	&"water":   {"name": "Bottle of water", "kind": "drink", "price": 2, "sold_at": "shop", "thirst": 0.5},
	&"soda":    {"name": "Soda", "kind": "drink", "price": 2, "sold_at": "shop", "thirst": 0.35, "tired": 0.05},
	&"coffee":  {"name": "Coffee", "kind": "drink", "price": 3, "sold_at": "shop", "thirst": 0.2, "tired": 0.2},
	&"chips":   {"name": "Bag of chips", "kind": "food", "price": 3, "sold_at": "shop", "hunger": 0.2},
	&"burrito": {"name": "Burrito", "kind": "food", "price": 7, "sold_at": "shop", "hunger": 0.5},
	&"bandage": {"name": "Bandage", "kind": "medical", "price": 12, "sold_at": "shop", "heal": 0.15},
	&"bat":     {"name": "Baseball bat", "kind": "weapon", "price": 45, "sold_at": "workshop", "weapon": &"bat"},
	&"knife":   {"name": "Knife", "kind": "weapon", "price": 35, "sold_at": "workshop", "weapon": &"knife"},
	&"pistol":  {"name": "Pistol (no papers)", "kind": "weapon", "price": 450, "sold_at": "dealer", "weapon": &"pistol"},
	&"ammo":    {"name": "Box of 9 mm (12)", "kind": "ammo", "price": 40, "sold_at": "dealer", "rounds": 12},
}

## Items on sale at a counter of this kind, in menu order.
static func stock(sold_at: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ITEMS:
		if ITEMS[id]["sold_at"] == sold_at:
			out.append(id)
	return out

static func item(id: StringName) -> Dictionary:
	return ITEMS.get(id, {})

## The item that puts this weapon in your hand (fists need none).
static func item_for_weapon(weapon: StringName) -> StringName:
	for id in ITEMS:
		if ITEMS[id].get("weapon", &"") == weapon:
			return id
	return &""
