## TA1: Zomboid-style timed actions. Eating, drinking, bandaging and taking a
## weapon in hand take a few seconds instead of happening at once; a bar over
## your head fills while you do it, and moving or attacking breaks it off
## (nothing is used up). Lockpicks and hotwires already have their own clocks
## (burglary_done_tick, hotwire_done_tick); the bar shows those too.
class_name TimedAction
extends RefCounted

## Real seconds per action, by item kind.
const SECONDS := {"food": 3.0, "drink": 2.0, "medical": 4.0, "weapon": 0.8}

## Starts using `item_id`. Returns a result for StreetTalk, or {} when it just began.
static func start(world: World, state: PlayerStateData, item_id: StringName) -> Dictionary:
	var it := ItemCatalog.item(item_id)
	if it.is_empty() or state.inventory.get(item_id, 0) <= 0:
		return {"ok": false, "reason": "dont_have"}
	if not SECONDS.has(it["kind"]):
		return {"ok": false, "reason": "cant_use"}
	var ticks := SimClock.real_seconds(SECONDS[it["kind"]])
	state.timed = {"item": item_id, "start": world.tick, "done": world.tick + ticks}
	return {}

## Call every player tick. `busy` = the player moved or swung this tick.
static func advance(world: World, npc: NPCData, state: PlayerStateData, busy: bool) -> Dictionary:
	if state.timed.is_empty():
		return {}
	var item: StringName = state.timed["item"]
	if busy:
		state.timed = {}
		return {"ok": false, "reason": "interrupted"}
	if world.tick < int(state.timed["done"]):
		return {}
	state.timed = {}
	var it := ItemCatalog.item(item)
	if it.get("kind", "") == "weapon":
		if state.inventory.get(item, 0) <= 0:
			return {"ok": false, "reason": "dont_have"}
		state.weapon = it["weapon"]
		return {"ok": true, "effect": "weapon_" + String(state.weapon)}
	var out := NeedsSystem.use_item(npc, state, item)
	BagGrid.sync(state)
	return out

## 0..1 progress and a label for the bar over the head, or {} when idle.
static func progress(world: World, state: PlayerStateData) -> Dictionary:
	if not state.timed.is_empty():
		var t: Dictionary = state.timed
		var it := ItemCatalog.item(t["item"])
		var verb: String = {"food": "Eating", "drink": "Drinking", "medical": "Bandaging", "weapon": "Equipping"}.get(it.get("kind", ""), "Using")
		return {"f": _f(world, t["start"], t["done"]), "text": verb}
	return {}

static func _f(world: World, start: int, done: int) -> float:
	return clampf(float(world.tick - start) / float(maxi(1, done - start)), 0.0, 1.0)
