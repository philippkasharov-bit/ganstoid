## INV4: DayZ's "vicinity": what lies within reach around you. Two kinds of
## source: piles on the ground (things you dropped; kept in
## PlayerStateData.ground so they save with the game) and the trunk of a car
## next to you that you own or that stands unlocked (VehicleData.trunk).
## Moves between the bag and a source go through BagGrid's room rules.
class_name Vicinity
extends RefCounted

const REACH_M := 2.5
const MERGE_M := 0.8   # dropping next to a pile of the same thing adds to it

## Sources in reach: [{kind: "ground", index, id, n} | {kind: "trunk", car, id, n}].
static func near(world: World, npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	for i in state.ground.size():
		var p: Dictionary = state.ground[i]
		if npc.position.distance_to(p["pos"]) <= REACH_M:
			out.append({"kind": "ground", "index": i, "id": p["id"], "n": int(p["n"])})
	var car := VehicleSystem.nearest_car(world, npc.position)
	if car != null and (car.owner_id == PlayerFactory.PLAYER_ENTITY_ID or not car.locked):
		for id in car.trunk:
			out.append({"kind": "trunk", "car": car.id, "id": id, "n": int(car.trunk[id])})
	return out

## Drops `n` of `id` at your feet, onto a matching pile if one is close.
static func drop(npc: NPCData, state: PlayerStateData, id: StringName, n: int) -> Dictionary:
	n = mini(n, int(state.inventory.get(id, 0)))
	if n <= 0:
		return {"ok": false, "reason": "dont_have"}
	_remove_from_bag(state, id, n)
	for p in state.ground:
		if p["id"] == id and npc.position.distance_to(p["pos"]) <= MERGE_M:
			p["n"] = int(p["n"]) + n
			return {"ok": true, "effect": "dropped"}
	state.ground.append({"id": id, "n": n, "pos": npc.position})
	return {"ok": true, "effect": "dropped"}

## Puts `n` of `id` in the trunk of the car next to you.
static func stash(world: World, npc: NPCData, state: PlayerStateData, id: StringName, n: int) -> Dictionary:
	var car := VehicleSystem.nearest_car(world, npc.position)
	if car == null or (car.owner_id != PlayerFactory.PLAYER_ENTITY_ID and car.locked):
		return {"ok": false, "reason": "no_trunk"}
	n = mini(n, int(state.inventory.get(id, 0)))
	if n <= 0:
		return {"ok": false, "reason": "dont_have"}
	_remove_from_bag(state, id, n)
	car.trunk[id] = int(car.trunk.get(id, 0)) + n
	car.touched = true   # so the save keeps this car and its trunk
	return {"ok": true, "effect": "stashed"}

## Takes up to `n` from source `src` (an entry of near()) into the bag.
static func take(world: World, state: PlayerStateData, src: Dictionary, n: int) -> Dictionary:
	var id: StringName = src["id"]
	n = mini(n, BagGrid.room_for(state, id))
	if n <= 0:
		return {"ok": false, "reason": "no_room"}
	if src["kind"] == "ground":
		var p: Dictionary = state.ground[src["index"]]
		n = mini(n, int(p["n"]))
		p["n"] = int(p["n"]) - n
		if p["n"] <= 0:
			state.ground.remove_at(src["index"])
	else:
		var car: VehicleData = world.entities[src["car"]].get_component(ComponentNames.VEHICLE)
		n = mini(n, int(car.trunk.get(id, 0)))
		car.trunk[id] = int(car.trunk[id]) - n
		if car.trunk[id] <= 0:
			car.trunk.erase(id)
	state.inventory[id] = int(state.inventory.get(id, 0)) + n
	BagGrid.sync(state)
	return {"ok": true, "effect": "picked_up"}

static func _remove_from_bag(state: PlayerStateData, id: StringName, n: int) -> void:
	state.inventory[id] = int(state.inventory[id]) - n
	if state.inventory[id] <= 0:
		state.inventory.erase(id)
		if ItemCatalog.item(id).get("weapon", &"") == state.weapon:
			state.weapon = &"fists"   # dropped what was in your hand
	BagGrid.sync(state)

## INV6: what is nearby laid out on a small grid for the Nearby panel: one pile
## per source, first free spot. Piles that do not fit are left off (rare).
static func layout(near: Array, cols: int, rows: int) -> Array:
	var piles: Array = []
	for src in near:
		var spot := BagGrid.free_spot(BagGrid.occupancy(piles), src["id"], cols, rows)
		if spot.is_empty():
			continue
		spot["id"] = src["id"]
		spot["n"] = src["n"]
		spot["src"] = src
		piles.append(spot)
	return piles
