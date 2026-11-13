## LT1: containers inside buildings and cars, Zomboid's scavenging. A house
## has kitchen, bathroom and bedroom; a shop its register and stockroom; your
## own place adds a stash that only you fill. Contents are rolled the first
## time you open them (seeded by the place, so a reload gives the same) and
## come back LootTables.RESTOCK_DAYS after the container was emptied. You get
## at a building's containers once you are inside: after a break-in, or any
## time at your own place. A car's glovebox opens with its trunk.
class_name Containers
extends RefCounted

const STASH := "stash"

## Is `building` yours (owned, or your home)?
static func is_yours(me: NPCData, building: BuildingData) -> bool:
	return building.owner_npc_id == PlayerFactory.PLAYER_ENTITY_ID or building.id == me.home_building_id

## The container kinds of a building you can open, filled as needed.
static func open(world: World, me: NPCData, building: BuildingData) -> Array:
	var kinds: Array = LootTables.containers_for(building)
	if is_yours(me, building):
		kinds = [STASH] + kinds
	for kind in kinds:
		_ensure(world, building, kind)
	return kinds

static func _ensure(world: World, building: BuildingData, kind: String) -> void:
	if not building.containers.has(kind):
		building.containers[kind] = {"items": {}, "filled": false, "emptied_tick": -1000000}
	var c: Dictionary = building.containers[kind]
	if kind == STASH:
		return
	var restocked: bool = world.tick - int(c["emptied_tick"]) >= int(LootTables.RESTOCK_DAYS * SimClock.day_ticks)
	if not c["filled"] or (c["items"].is_empty() and restocked):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(building.id) + kind + str(world.tick / SimClock.day_ticks))
		c["items"] = LootTables.roll(kind, rng)
		c["filled"] = true

## Takes up to n of id from a building container; returns how many came out.
static func take(world: World, building: BuildingData, kind: String, id: StringName, n: int) -> int:
	var items: Dictionary = building.containers[kind]["items"]
	var got := mini(n, int(items.get(id, 0)))
	items[id] = int(items.get(id, 0)) - got
	if items[id] <= 0:
		items.erase(id)
	if items.is_empty():
		building.containers[kind]["emptied_tick"] = world.tick
	return got

## Puts n of id into your stash.
static func put(building: BuildingData, id: StringName, n: int) -> void:
	var items: Dictionary = building.containers[STASH]["items"]
	items[id] = int(items.get(id, 0)) + n

## The glovebox of a car you may open, rolled on first look.
static func glovebox(world: World, car: VehicleData) -> Dictionary:
	if not car.glovebox_filled:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(car.id) + "glovebox")
		car.glovebox = LootTables.roll("glovebox", rng)
		car.glovebox_filled = true
		car.touched = true   # keep it in the save once looked at
	return car.glovebox

## Display name of a container kind.
static func title(kind: String) -> String:
	return "Your stash" if kind == STASH else LootTables.TABLES[kind]["name"]
