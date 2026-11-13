## INV4/LT1: DayZ's "vicinity": what lies within reach around you. Sources:
## piles on the ground (things you dropped; kept in PlayerStateData.ground so
## they save), the trunk and glovebox of a car next to you that you own or
## that stands unlocked, and the containers of the building you are inside
## (Containers: after a break-in, or your own place).
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
		var box := Containers.glovebox(world, car)
		for id in box:
			out.append({"kind": "glovebox", "car": car.id, "id": id, "n": int(box[id])})
	var inside := _building(world, state.inside_id)
	if inside != null:
		for kind in Containers.open(world, npc, inside):
			var items: Dictionary = inside.containers[kind]["items"]
			for id in items:
				out.append({"kind": "container", "building": inside.id, "cont": kind, "id": id, "n": int(items[id])})
	return out

## LT1: you are inside a place while you stay at its door: after a break-in,
## or any time at your own. Call every player tick.
static func update_inside(world: World, npc: NPCData, state: PlayerStateData) -> void:
	var b := _building(world, state.inside_id)
	if b != null and b.position.distance_to(npc.position) > REACH_M * 2.0:
		state.inside_id = &""
	if state.inside_id == &"":
		for id in world.spatial_index.query_nearby(npc.position):
			var e: Entity = world.entities.get(id)
			var own: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
			if own != null and Containers.is_yours(npc, own) and own.position.distance_to(npc.position) <= REACH_M:
				state.inside_id = own.id
				return

static func _building(world: World, id: StringName) -> BuildingData:
	var e: Entity = world.entities.get(id) if id != &"" else null
	return e.get_component(ComponentNames.BUILDING) if e != null else null

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

## LT1: puts `n` of `id` in your stash (you are inside your own place).
static func store(world: World, npc: NPCData, state: PlayerStateData, id: StringName, n: int) -> Dictionary:
	var b := _building(world, state.inside_id)
	if b == null or not Containers.is_yours(npc, b):
		return {"ok": false, "reason": "no_stash"}
	n = mini(n, int(state.inventory.get(id, 0)))
	if n <= 0:
		return {"ok": false, "reason": "dont_have"}
	_remove_from_bag(state, id, n)
	Containers.open(world, npc, b)
	Containers.put(b, id, n)
	return {"ok": true, "effect": "stashed"}

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
	if id == &"cash":   # LT1: money goes in your pocket, not the bag
		n = _take_from(world, src, int(src["n"]))
		Wallet.earn_dirty(world, n)
		return {"ok": true, "effect": "found_cash", "amount": n}
	n = mini(n, BagGrid.room_for(state, id))
	if n <= 0:
		return {"ok": false, "reason": "no_room"}
	if src["kind"] in ["container", "glovebox"]:
		n = _take_from(world, src, n)
	elif src["kind"] == "ground":
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

## Takes from a building container or glovebox; returns how many came out.
static func _take_from(world: World, src: Dictionary, n: int) -> int:
	if src["kind"] == "container":
		return Containers.take(world, _building(world, src["building"]), src["cont"], src["id"], n)
	if src["kind"] == "glovebox":
		var car: VehicleData = world.entities[src["car"]].get_component(ComponentNames.VEHICLE)
		var got := mini(n, int(car.glovebox.get(src["id"], 0)))
		car.glovebox[src["id"]] = int(car.glovebox[src["id"]]) - got
		if car.glovebox[src["id"]] <= 0:
			car.glovebox.erase(src["id"])
		return got
	return 0

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
