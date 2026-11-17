## Items (G1): every thing the player can carry, as one data table. Pure data:
## systems read it; nothing here changes state.
##   kind     food | drink | medical | weapon | ammo | gear | seed (BZ1: growing) | chem (BZ4: the lab) | valuable (LT4: loot to pawn or fence; no sold_at)
##   price    dollars at a counter (black-market goods: at a dealer)
##   sold_at  shop | workshop | dealer   (who has it on the shelf)
##   hunger / thirst / tired  how much one use restores (0..1 of the need)
##   heal     health one use gives back; stops bleeding
##   weapon   key into CombatSystem.WEAPONS
##   rounds   pistol rounds in one box
##   weight   kg one carried unit adds (UI5: the bag's weight bar)
##   size     cells it takes in the bag grid, w x h (INV1: Tarkov/DayZ style)
##   stack    how many share one spot (bandages pile up, guns do not)
class_name ItemCatalog
extends RefCounted

const ITEMS := {
	&"water":   {"size": Vector2i(1, 2), "stack": 1, "weight": 0.5, "name": "Bottle of water", "kind": "drink", "price": 2, "sold_at": "shop", "thirst": 0.5},
	&"soda":    {"size": Vector2i(1, 2), "stack": 1, "weight": 0.4, "name": "Soda", "kind": "drink", "price": 2, "sold_at": "shop", "thirst": 0.35, "tired": 0.05},
	&"coffee":  {"size": Vector2i(1, 1), "stack": 1, "weight": 0.3, "name": "Coffee", "kind": "drink", "price": 3, "sold_at": "shop", "thirst": 0.2, "tired": 0.2},
	&"chips":   {"size": Vector2i(1, 1), "stack": 1, "weight": 0.2, "name": "Bag of chips", "kind": "food", "price": 3, "sold_at": "shop", "hunger": 0.2},
	&"burrito": {"size": Vector2i(2, 1), "stack": 1, "weight": 0.4, "name": "Burrito", "kind": "food", "price": 7, "sold_at": "shop", "hunger": 0.5},
	&"bandage": {"size": Vector2i(1, 1), "stack": 5, "weight": 0.1, "name": "Bandage", "kind": "medical", "price": 12, "sold_at": "shop", "heal": 0.15},
	&"bat":     {"size": Vector2i(1, 4), "stack": 1, "weight": 1.0, "name": "Baseball bat", "kind": "weapon", "price": 45, "sold_at": "workshop", "weapon": &"bat"},
	&"knife":   {"size": Vector2i(1, 2), "stack": 1, "weight": 0.3, "name": "Knife", "kind": "weapon", "price": 35, "sold_at": "workshop", "weapon": &"knife"},
	&"pistol":  {"size": Vector2i(2, 1), "stack": 1, "weight": 0.9, "name": "Pistol (no papers)", "kind": "weapon", "price": 450, "sold_at": "dealer", "weapon": &"pistol", "trade": 600, "standing": 0.1, "armory": 1},
	&"pistol_clean": {"size": Vector2i(2, 1), "stack": 1, "weight": 0.9, "name": "Clean pistol (new, no history)", "kind": "weapon", "price": 900, "sold_at": "dealer", "weapon": &"pistol", "rank": 2, "trade": 1300, "standing": 0.2, "armory": 2},
	&"grow_tent":  {"size": Vector2i(2, 2), "stack": 1, "weight": 4.0, "name": "Grow tent (4 plants)", "kind": "gear", "price": 220, "sold_at": "workshop"},
	&"shop_light": {"size": Vector2i(2, 1), "stack": 1, "weight": 1.5, "name": "Shop light (fluorescent)", "kind": "gear", "price": 60, "sold_at": "workshop"},
	&"hps_lamp":   {"size": Vector2i(2, 2), "stack": 1, "weight": 3.0, "name": "HPS grow lamp", "kind": "gear", "price": 320, "sold_at": "workshop"},
	&"grow_fan":   {"size": Vector2i(1, 1), "stack": 1, "weight": 1.0, "name": "Clip fan", "kind": "gear", "price": 35, "sold_at": "workshop"},
	&"carbon_filter": {"size": Vector2i(1, 2), "stack": 1, "weight": 2.0, "name": "Carbon filter (smell)", "kind": "gear", "price": 140, "sold_at": "workshop"},
	&"plant_food": {"size": Vector2i(1, 1), "stack": 10, "weight": 0.3, "name": "Plant food", "kind": "gear", "price": 8, "sold_at": "workshop"},
	&"seeds_mids": {"size": Vector2i(1, 1), "stack": 20, "weight": 0.0, "name": "Seeds: street mids", "kind": "seed", "price": 10, "sold_at": "dealer"},
	&"seeds_kush": {"size": Vector2i(1, 1), "stack": 20, "weight": 0.0, "name": "Seeds: OG Kush", "kind": "seed", "price": 35, "sold_at": "dealer"},
	&"seeds_skunk": {"size": Vector2i(1, 1), "stack": 20, "weight": 0.0, "name": "Seeds: Skunk #1", "kind": "seed", "price": 20, "sold_at": "dealer"},
	&"seeds_nl":   {"size": Vector2i(1, 1), "stack": 20, "weight": 0.0, "name": "Seeds: Northern Lights", "kind": "seed", "price": 30, "sold_at": "dealer"},
	&"seeds_blue": {"size": Vector2i(1, 1), "stack": 20, "weight": 0.0, "name": "Seeds: Blueberry", "kind": "seed", "price": 45, "sold_at": "dealer"},
	&"seeds_haze": {"size": Vector2i(1, 1), "stack": 20, "weight": 0.0, "name": "Seeds: Purple Haze", "kind": "seed", "price": 60, "sold_at": "dealer"},
	&"pill_press": {"size": Vector2i(2, 2), "stack": 1, "weight": 6.0, "name": "Pill press", "kind": "gear", "price": 1200, "sold_at": "dealer"},
	&"lab_glass":  {"size": Vector2i(2, 2), "stack": 1, "weight": 3.0, "name": "Lab glassware", "kind": "gear", "price": 600, "sold_at": "workshop"},
	&"pill_powder": {"size": Vector2i(1, 1), "stack": 20, "weight": 0.1, "name": "MDMA powder", "kind": "chem", "price": 30, "sold_at": "dealer"},
	&"speed_powder": {"size": Vector2i(1, 1), "stack": 20, "weight": 0.1, "name": "Speed-cut powder", "kind": "chem", "price": 15, "sold_at": "dealer"},
	&"cold_meds":  {"size": Vector2i(1, 1), "stack": 20, "weight": 0.1, "name": "Cold medicine (box)", "kind": "chem", "price": 9, "sold_at": "shop"},
	&"walkman":    {"size": Vector2i(1, 1), "stack": 1, "weight": 0.3, "name": "Walkman", "kind": "valuable", "price": 45},
	&"pager":      {"size": Vector2i(1, 1), "stack": 1, "weight": 0.1, "name": "Pager", "kind": "valuable", "price": 60},
	&"cd_player":  {"size": Vector2i(1, 1), "stack": 1, "weight": 0.4, "name": "Discman", "kind": "valuable", "price": 80},
	&"brick_phone": {"size": Vector2i(1, 2), "stack": 1, "weight": 0.8, "name": "Cell phone (a brick)", "kind": "valuable", "price": 300},
	&"camcorder":  {"size": Vector2i(2, 1), "stack": 1, "weight": 1.2, "name": "Camcorder", "kind": "valuable", "price": 350},
	&"vcr":        {"size": Vector2i(2, 2), "stack": 1, "weight": 4.0, "name": "VCR", "kind": "valuable", "price": 120},
	&"tv":         {"size": Vector2i(3, 3), "stack": 1, "weight": 12.0, "name": "Color TV", "kind": "valuable", "price": 220},
	&"boombox":    {"size": Vector2i(2, 1), "stack": 1, "weight": 3.0, "name": "Boombox", "kind": "valuable", "price": 90},
	&"game_console": {"size": Vector2i(2, 1), "stack": 1, "weight": 1.5, "name": "Game console", "kind": "valuable", "price": 110},
	&"gold_chain": {"size": Vector2i(1, 1), "stack": 3, "weight": 0.1, "name": "Gold chain", "kind": "valuable", "price": 250},
	&"ring":       {"size": Vector2i(1, 1), "stack": 5, "weight": 0.0, "name": "Gold ring", "kind": "valuable", "price": 180},
	&"watch":      {"size": Vector2i(1, 1), "stack": 3, "weight": 0.1, "name": "Wristwatch", "kind": "valuable", "price": 150},
	&"pearls":     {"size": Vector2i(1, 1), "stack": 1, "weight": 0.1, "name": "Pearl necklace", "kind": "valuable", "price": 400},
	&"jordans":    {"size": Vector2i(2, 1), "stack": 1, "weight": 1.0, "name": "Jordans (in the box)", "kind": "valuable", "price": 110},
	&"leather_jacket": {"size": Vector2i(2, 2), "stack": 1, "weight": 2.0, "name": "Leather jacket", "kind": "valuable", "price": 95},
	&"baseball_cards": {"size": Vector2i(1, 1), "stack": 1, "weight": 0.2, "name": "Baseball cards", "kind": "valuable", "price": 70},
	&"cigarettes": {"size": Vector2i(1, 1), "stack": 5, "weight": 0.2, "name": "Carton of cigarettes", "kind": "valuable", "price": 25},
	&"liquor":     {"size": Vector2i(1, 2), "stack": 1, "weight": 1.0, "name": "Bottle of liquor", "kind": "valuable", "price": 22},
	&"cash_tin":   {"size": Vector2i(1, 1), "stack": 1, "weight": 0.3, "name": "Coffee can of cash", "kind": "valuable", "price": 160},
	&"print_press": {"size": Vector2i(2, 2), "stack": 1, "weight": 8.0, "name": "Printing press", "kind": "gear", "price": 1800, "sold_at": "dealer"},
	&"ink_paper":  {"size": Vector2i(1, 1), "stack": 10, "weight": 0.4, "name": "Paper and ink", "kind": "chem", "price": 40, "sold_at": "workshop"},
	&"fake_bill":  {"size": Vector2i(1, 1), "stack": 50, "weight": 0.0, "name": "Fake $100 bill", "kind": "fake", "price": 0},
	&"ammo":    {"size": Vector2i(1, 1), "stack": 1, "weight": 0.3, "name": "Box of 9 mm (12)", "kind": "ammo", "price": 40, "sold_at": "dealer", "rounds": 12},
}

## UI5: what the bag holds before you are overloaded (display only for now).
const CARRY_KG := 12.0

## INV1: street goods (drugs) are small packs that pile up in one cell.
const GOODS_SIZE := Vector2i(1, 1)
const GOODS_STACK := 50

static func size_of(id: StringName) -> Vector2i:
	return ITEMS[id].get("size", Vector2i.ONE) if ITEMS.has(id) else GOODS_SIZE

static func stack_of(id: StringName) -> int:
	return ITEMS[id].get("stack", 1) if ITEMS.has(id) else GOODS_STACK

## Items on sale at a counter of this kind, in menu order.
static func stock(sold_at: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ITEMS:
		if ITEMS[id].get("sold_at", "") == sold_at:   # LT4: valuables are sold nowhere
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
