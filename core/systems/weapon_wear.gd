## B6: Zomboid's item condition for weapons. Every blow or shot wears the
## weapon in hand a little (a hit more than a miss). A worn blade or bat hits
## softer and in the end breaks; a worn, dirty pistol starts to jam (the next
## pull of the trigger clears it). A workshop fixes it for part of its price.
## Condition lives per item kind in PlayerStateData.wear (saved).
class_name WeaponWear
extends RefCounted

## item kind -> [wear on a hit, wear on a miss]
const WEAR := {&"bat": [0.02, 0.008], &"knife": [0.012, 0.005], &"pistol": [0.004, 0.004], &"pistol_clean": [0.003, 0.003]}
const JAM_BELOW := 0.5          # a pistol under this condition can jam
const JAM_PER_WEAR := 0.6       # jam chance = (JAM_BELOW - condition) * this
const MIN_DAMAGE := 0.6         # a melee weapon at 0 condition hits for 60%
const REPAIR_SHARE := 0.5       # of the item's price, times how worn it is

static func condition(state: PlayerStateData, id: StringName) -> float:
	return float(state.wear.get(id, 1.0))

## The item that is the weapon in hand ("" for fists).
static func held(state: PlayerStateData) -> StringName:
	for id in state.inventory:
		if int(state.inventory[id]) > 0 and ItemCatalog.item(id).get("weapon", &"") == state.weapon:
			return id
	return &""

## Melee damage multiplier from the held weapon's condition.
static func damage_mult(state: PlayerStateData) -> float:
	var id := held(state)
	return 1.0 if id == &"" else lerpf(MIN_DAMAGE, 1.0, condition(state, id))

## A pistol that jams this shot (rolls; only when worn).
static func jams(state: PlayerStateData, rng: RandomNumberGenerator) -> bool:
	var id := held(state)
	var c := condition(state, id)
	return id != &"" and not CombatSystem.WEAPONS[state.weapon]["melee"] and c < JAM_BELOW and rng.randf() < (JAM_BELOW - c) * JAM_PER_WEAR

## Wears the held weapon after an attack. Returns "broke" if it fell apart.
static func use(state: PlayerStateData, hit: bool) -> String:
	var id := held(state)
	if id == &"" or not WEAR.has(id):
		return ""
	var c := maxf(0.0, condition(state, id) - float(WEAR[id][0 if hit else 1]))
	state.wear[id] = c
	if c > 0.0 or not CombatSystem.WEAPONS[state.weapon]["melee"]:
		return ""
	state.inventory[id] = int(state.inventory[id]) - 1
	if state.inventory[id] <= 0:
		state.inventory.erase(id)
		state.wear.erase(id)
		state.weapon = &"fists"
	else:
		state.wear[id] = 1.0   # the spare one in the bag
	BagGrid.sync(state)
	return "broke"

## What fixing it costs (0 when it is as good as new).
static func repair_cost(state: PlayerStateData, id: StringName) -> int:
	return roundi(int(ItemCatalog.item(id).get("price", 0)) * (1.0 - condition(state, id)) * REPAIR_SHARE)

## Pays the workshop and makes it as good as new.
static func repair(world: World, me: NPCData, state: PlayerStateData, id: StringName, shop: BuildingData) -> Dictionary:
	var cost := repair_cost(state, id)
	if cost <= 0:
		return {"ok": false, "reason": "not_worn"}
	if me.cash < cost:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, cost)
	if shop != null:
		shop.cash_on_hand += cost   # E2: real money into the workshop's till
	state.wear[id] = 1.0
	return {"ok": true, "effect": "repaired", "amount": cost}
