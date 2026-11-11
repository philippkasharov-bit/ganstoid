## Gun trade (WP1). Sell a gun you carry to a gang member (Esc next to one):
## the best gun first. Pays more than a dealer charged; the gang likes you
## better (more for clean guns) and is better armed in its fights. No gun
## ledger: a gun you sold is never traced back to you (Phil: it kills the fun).
class_name GunTrade
extends RefCounted

const SATURATION := 0.12   # with 3 guns in their armory a street pistol fetches ~$440: below the dealer's $450
const TRADE_ORDER: Array[StringName] = [&"pistol_clean", &"pistol"]

static func sell(world: World, me: NPCData, state: PlayerStateData, buyer: NPCData) -> Dictionary:
	if buyer.gang_id == &"" or buyer.is_down:
		return {"ok": false, "reason": "not_a_buyer"}
	if buyer.position.distance_to(me.position) > CrimeSystem.INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	var gun: StringName = &""
	for id in TRADE_ORDER:
		if state.inventory.get(id, 0) > 0:
			gun = id
			break
	if gun == &"":
		return {"ok": false, "reason": "no_gun_to_sell"}
	var it := ItemCatalog.item(gun)
	var gang_e: Entity = world.entities.get(buyer.gang_id)
	var armory: int = gang_e.get_component(ComponentNames.GANG).armory if gang_e != null else 0
	var pay := int(it["trade"] / (1.0 + armory * SATURATION))   # TUNE1: each gun they own makes the next worth less to them
	state.inventory[gun] -= 1
	if state.inventory[gun] <= 0:
		state.inventory.erase(gun)
	if state.weapon == &"pistol" and not ShopSystem.owned_weapons(state).has(&"pistol"):
		state.weapon = &"fists"
	Wallet.earn_dirty(world, pay)
	var standing: float = state.gang_standing.get(buyer.gang_id, 0.5)
	state.gang_standing[buyer.gang_id] = minf(1.0, standing + it["standing"] * (1.0 - standing) * 2.0)
	if gang_e != null:
		gang_e.get_component(ComponentNames.GANG).armory += it["armory"]
	Skills.train(world, state, &"hustle", 6.0)
	return {"ok": true, "effect": "gun_sold", "amount": pay}

## How much better a gang shoots and fights for the guns it has: 1.0 .. 1.5.
static func armed_edge(world: World, gang_id: StringName) -> float:
	var gang_e: Entity = world.entities.get(gang_id)
	if gang_e == null:
		return 1.0
	return 1.0 + minf(0.5, gang_e.get_component(ComponentNames.GANG).armory * 0.05)
