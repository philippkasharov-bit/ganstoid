## Buying things (G1). Counters: a shop or workshop while it is open, or a
## dealer on the street (the black market: guns and rounds, any hour).
## Pure rules on World data; PlayerInputSystem decides when to call them.
class_name ShopSystem
extends RefCounted

const OPEN_HOUR := 7.0
const CLOSE_HOUR := 22.0

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
	var hour := SimClock.day_fraction(world.tick) * 24.0
	return hour >= OPEN_HOUR and hour < CLOSE_HOUR

## Buys one of `item_id` at `source_id`. Returns {ok, effect|reason, amount}.
static func buy(world: World, me: NPCData, state: PlayerStateData, source_id: StringName, item_id: StringName) -> Dictionary:
	var kind := counter_kind(world, source_id)
	var it := ItemCatalog.item(item_id)
	if kind == "" or it.is_empty() or it["sold_at"] != kind:
		return {"ok": false, "reason": "not_sold_here"}
	if not is_open(world, source_id):
		return {"ok": false, "reason": "closed"}
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
