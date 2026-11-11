## Buying things (G1). Counters: a shop or workshop while it is open, or a
## dealer on the street (the black market: guns and rounds, any hour).
## Pure rules on World data; PlayerInputSystem decides when to call them.
class_name ShopSystem
extends RefCounted

const ALL_NIGHT_SHARE := 0.25    # corner stores, gas-station marts, liquor stores: open 24 h
## Every counter keeps its own hours, fixed per building (rolled from its id,
## so the same store keeps the same hours every run and after a load).

## What kind of counter `source_id` is: "shop", "workshop", "dealer" or "" (none).
static func counter_kind(world: World, source_id: StringName) -> String:
	var entity: Entity = world.entities.get(source_id)
	if entity == null:
		return ""
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if npc != null:
		return "dealer" if npc.is_dealer and not npc.is_down and not npc.indoors else ""
	var b: BuildingData = entity.get_component(ComponentNames.BUILDING)
	if b == null or b.building_type != GanstoidEnums.BuildingType.LEGIT_BUSINESS:
		return ""
	return String(b.business_kind) if b.business_kind != &"" else "shop"

static func is_open(world: World, source_id: StringName) -> bool:
	if counter_kind(world, source_id) == "dealer":
		return true
	var h := hours_of(source_id, counter_kind(world, source_id))
	if h.y - h.x >= 24.0:
		return true
	var hour := SimClock.day_fraction(world.tick) * 24.0
	return hour >= h.x and hour < h.y

## (opening hour, closing hour) of a counter; closing 24+ = open round the clock.
static func hours_of(source_id: StringName, kind: String) -> Vector2:
	var roll := float(absi(hash([source_id, 71])) % 1000) / 1000.0
	var roll2 := float(absi(hash([source_id, 72])) % 1000) / 1000.0
	if kind == "workshop":   # hardware: daytime trade
		return Vector2(7.0 + floorf(roll * 2.0), 17.0 + floorf(roll2 * 3.0))
	if roll < ALL_NIGHT_SHARE:
		return Vector2(0.0, 24.0)
	return Vector2(6.0 + floorf(roll2 * 4.0), 20.0 + floorf(roll * 4.0))   # opens 6-9, closes 20-23

## Buys one of `item_id` at `source_id`. Returns {ok, effect|reason, amount}.
static func buy(world: World, me: NPCData, state: PlayerStateData, source_id: StringName, item_id: StringName) -> Dictionary:
	var kind := counter_kind(world, source_id)
	var it := ItemCatalog.item(item_id)
	if kind == "" or it.is_empty() or it["sold_at"] != kind:
		return {"ok": false, "reason": "not_sold_here"}
	if not is_open(world, source_id):
		return {"ok": false, "reason": "closed"}
	if it["kind"] == "weapon" and kind == "dealer" and state.rank < RankSystem.GUN_RANK:
		return {"ok": false, "reason": "nobody_gun"}   # RK1: they don't sell iron to a nobody
	var price: int = it["price"]
	if me.cash < price:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, price)
	if it["kind"] == "ammo":
		state.ammo += int(it["rounds"])
	else:
		state.inventory[item_id] = state.inventory.get(item_id, 0) + 1
	var entity: Entity = world.entities.get(source_id)
	var b: BuildingData = entity.get_component(ComponentNames.BUILDING) if entity != null else null
	if b != null:
		b.cash_on_hand += price   # the till fills: more to rob tonight
	return {"ok": true, "effect": "bought", "amount": price, "item": item_id}

## Weapons you can hold: fists always, plus every weapon item you carry.
static func owned_weapons(state: PlayerStateData) -> Array[StringName]:
	var out: Array[StringName] = [&"fists"]
	for w in CombatSystem.ORDER:
		if w != &"fists" and state.inventory.get(ItemCatalog.item_for_weapon(w), 0) > 0:
			out.append(w)
	return out
