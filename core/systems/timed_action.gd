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
static func start(world: World, state: PlayerStateData, item_id: StringName, part: String = "") -> Dictionary:
	var it := ItemCatalog.item(item_id)
	if it.is_empty() or state.inventory.get(item_id, 0) <= 0:
		return {"ok": false, "reason": "dont_have"}
	if not SECONDS.has(it["kind"]):
		return {"ok": false, "reason": "cant_use"}
	var ticks := SimClock.real_seconds(SECONDS[it["kind"]])
	state.timed = {"item": item_id, "start": world.tick, "done": world.tick + ticks, "part": part}
	return {}

## B4: Zomboid's transfer time: moving things in or out of the bag takes a
## moment, longer for heavy things; walking off cancels it (nothing moves).
const MOVE_BASE_S := 0.3
const MOVE_PER_KG_S := 0.5
const MOVE_MAX_S := 5.0

static func move_seconds(move: Dictionary) -> float:
	var kg := 0.0
	if move.get("op", "") == "take_all":
		for src in move["srcs"]:
			kg += ItemCatalog.item(src["id"]).get("weight", 0.0) * int(src["n"])
	elif move.has("src"):
		kg = ItemCatalog.item(move["src"]["id"]).get("weight", 0.0) * mini(int(move["n"]), int(move["src"]["n"]))
	else:
		kg = ItemCatalog.item(move.get("id", &"")).get("weight", 0.0) * int(move.get("n", 1))
	return minf(MOVE_MAX_S, MOVE_BASE_S + MOVE_PER_KG_S * kg)

## Starts moving things (take, drop, stash): done when the bar is full.
## Asked while another move is under way, it waits its turn (Zomboid's queue).
static func start_move(world: World, state: PlayerStateData, move: Dictionary, queue: Array = []) -> void:
	if state.timed.has("move"):
		state.timed["queue"].append(move)
		return
	state.timed = {"move": move, "start": world.tick, "done": world.tick + SimClock.real_seconds(move_seconds(move)), "queue": queue}

## Call every player tick. `busy` = the player moved or swung this tick.
static func advance(world: World, npc: NPCData, state: PlayerStateData, busy: bool) -> Dictionary:
	if state.timed.is_empty():
		return {}
	if state.timed.has("move"):   # B4: the hands are done: the move happens now
		if busy:
			state.timed = {}
			return {"ok": false, "reason": "interrupted"}
		if world.tick < int(state.timed["done"]):
			return {}
		var move: Dictionary = state.timed["move"]
		var rest: Array = state.timed.get("queue", [])
		state.timed = {}
		if not rest.is_empty():
			start_move(world, state, rest[0], rest.slice(1))
		return {"do_move": move}
	var item: StringName = state.timed["item"]
	var part: String = state.timed.get("part", "")
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
	var out := NeedsSystem.use_item(npc, state, item, part)
	BagGrid.sync(state)
	return out

## 0..1 progress and a label for the bar over the head, or {} when idle.
static func progress(world: World, state: PlayerStateData) -> Dictionary:
	if not state.timed.is_empty() and state.timed.has("move"):
		var mt: Dictionary = state.timed
		var verb: String = {"take": "Taking", "take_all": "Taking all", "drop": "Dropping", "stash": "Stashing", "store": "Stashing"}.get(mt["move"].get("op", ""), "Moving")
		return {"f": _f(world, mt["start"], mt["done"]), "text": verb}
	if not state.timed.is_empty():
		var t: Dictionary = state.timed
		var it := ItemCatalog.item(t["item"])
		var verb: String = {"food": "Eating", "drink": "Drinking", "medical": "Bandaging", "weapon": "Equipping"}.get(it.get("kind", ""), "Using")
		return {"f": _f(world, t["start"], t["done"]), "text": verb}
	return {}

static func _f(world: World, start: int, done: int) -> float:
	return clampf(float(world.tick - start) / float(maxi(1, done - start)), 0.0, 1.0)
