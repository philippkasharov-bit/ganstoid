## HB1: Project Zomboid's hotbar: the slots along the bottom of the screen
## for what is on your belt, each on a number key. Ours fills itself (no
## dragging things onto the belt yet): every weapon you carry, then the best
## bandage, food and drink. A key or a click takes the weapon in hand (again:
## puts it away) or uses the item, as a timed action. Pure rules, no UI.
class_name Hotbar
extends RefCounted

const MAX_SLOTS := 7
const KINDS := ["medical", "food", "drink"]

## [{id, kind}] in slot order; ids not in the bag are left out.
static func slots(state: PlayerStateData) -> Array:
	var out: Array = []
	for id in ItemCatalog.ITEMS:
		if ItemCatalog.ITEMS[id]["kind"] == "weapon" and int(state.inventory.get(id, 0)) > 0:
			out.append({"id": id, "kind": "weapon"})
	for kind in KINDS:
		var best := Moodles.best_item(state, kind)
		if best != &"":
			out.append({"id": best, "kind": kind})
	return out.slice(0, MAX_SLOTS)

## True when this slot is the weapon in your hand.
static func in_hand(state: PlayerStateData, slot: Dictionary) -> bool:
	return slot["kind"] == "weapon" and ItemCatalog.item(slot["id"]).get("weapon", &"") == state.weapon

## What a press of slot `i` does: {} when nothing is there, {"holster": true}
## to put the weapon in hand away, else {"use": id}.
static func press(state: PlayerStateData, i: int) -> Dictionary:
	var all := slots(state)
	if i < 0 or i >= all.size():
		return {}
	if in_hand(state, all[i]):
		return {"holster": true}
	return {"use": all[i]["id"]}
