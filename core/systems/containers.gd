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
	building.touched = true   # PF1: its drawers are now part of the save
	if not building.containers.has(kind):
		building.containers[kind] = {"items": {}, "filled": false, "emptied_tick": -1000000}
	var c: Dictionary = building.containers[kind]
	if kind == STASH:
		return
	c["items"].erase(&"cash")   # E3: money is the building's own (cash_on_hand), never rolled; old saves had some here
	var restocked: bool = world.tick - int(c["emptied_tick"]) >= int(LootTables.RESTOCK_DAYS * SimClock.day_ticks)
	if not c["filled"] or (c["items"].is_empty() and restocked):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(building.id) + kind + str(world.tick / SimClock.day_ticks))
		var roll := {}
		for i in _pieces(building, kind):   # LT2: every cupboard rolls (a block of flats has dozens of kitchens)
			var r := LootTables.roll(kind, rng)
			for id in r:
				roll[id] = roll.get(id, 0) + r[id]
		if c["filled"] and not _pay_restock(building, LootTables.value(roll)):
			return   # E3: they could not afford to stock it again; it stays empty
		c["items"] = roll
		c["filled"] = true

## LT2: how many pieces of furniture hold `kind` in this building (1 when its
## layout is unknown or has none): an apartment block rolls each flat's kitchen.
const MAX_PIECES := 12

static func _pieces(building: BuildingData, kind: String) -> int:
	var col: CityCollision = SimNav.active.collision if SimNav.active != null else null
	var b: Dictionary = col.by_id.get(building.id, {}) if col != null else {}
	if b.is_empty():
		return 1
	var n := 0
	for f in InteriorLayout.of(b).furniture:
		n += int(f["container"] == kind)
	return clampi(ceili(n / 3.0), 1, MAX_PIECES)   # a kitchen is about three pieces (counter, fridge, cupboard)

## E3: the people there buy what fills the drawers again (from the cash at
## home or the till, then savings). False when they cannot afford it.
static func _pay_restock(building: BuildingData, cost: int) -> bool:
	if building.cash_on_hand + building.bank < cost:
		return false
	var from_cash := mini(cost, building.cash_on_hand)
	building.cash_on_hand -= from_cash
	building.bank -= cost - from_cash
	return true

## E3: the money a building's cash drawer or register shows (its real cash).
static func cash_shown(building: BuildingData, kind: String) -> int:
	if not LootTables.CASH_IN.has(kind):
		return 0
	return int(building.cash_on_hand * EconomyFallout.ROB_KEEP[clampi(building.security, 0, 3)])   # E4: a locked drop safe keeps the rest

## E3: takes up to n of the building's real cash; returns how much came out.
static func take_cash(world: World, building: BuildingData, n: int) -> int:
	var got := mini(n, int(building.cash_on_hand * EconomyFallout.ROB_KEEP[clampi(building.security, 0, 3)]))
	building.cash_on_hand -= got
	building.touched = true
	if got > 0 and building.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
		building.has_been_hit = true
		building.hits += 1.0   # E4
	return got

## Takes up to n of id from a building container; returns how many came out.
static func take(world: World, building: BuildingData, kind: String, id: StringName, n: int) -> int:
	building.touched = true
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
	building.touched = true
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
