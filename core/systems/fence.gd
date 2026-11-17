## LT4: turning loot into money. A pawn shop (open hours) buys valuables at
## PAWN_SHARE of their worth in clean cash: it's a shop, there's a receipt.
## A dealer fences them for FENCE_SHARE, dirty, no questions.
class_name Fence
extends RefCounted

const PAWN_SHARE := 0.35
const FENCE_SHARE := 0.5

## What the valuables you carry would fetch at `share`.
static func worth(state: PlayerStateData, share: float) -> int:
	var total := 0
	for id in state.inventory:
		var it := ItemCatalog.item(id)
		if it.get("kind", "") == "valuable":
			total += int(round(int(it["price"]) * share)) * int(state.inventory[id])
	return total

static func _sell(world: World, state: PlayerStateData, share: float, clean: bool) -> Dictionary:
	var pay := worth(state, share)
	if pay <= 0:
		return {"ok": false, "reason": "nothing_to_sell"}
	for id in state.inventory.keys():
		if ItemCatalog.item(id).get("kind", "") == "valuable":
			state.inventory.erase(id)
	if clean:
		Wallet.earn_clean(world, pay)
	else:
		Wallet.earn_dirty(world, pay)
	return {"ok": true, "effect": "pawned" if clean else "fenced", "amount": pay}

static func pawn(world: World, state: PlayerStateData) -> Dictionary:
	return _sell(world, state, PAWN_SHARE, true)

static func fence(world: World, state: PlayerStateData) -> Dictionary:
	return _sell(world, state, FENCE_SHARE, false)
