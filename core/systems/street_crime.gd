## Street crime (X2): mugging and burglary.
##   - Mugging: weapon raised (right mouse) at someone within reach and Enter:
##     they hand over what they carry. A few (BRAVE_SHARE) refuse and run.
##   - Burglary (DW2, Zomboid's ways in): pick the lock (slow, quiet), kick the
##     door in (quick, loud, the door stays broken) or smash a window (quickest,
##     loudest; not through boards). A broken door or window lets you walk
##     straight in next time. Then you are in and out with what was there. A
##     house is worth robbing again after RESTOCK_DAYS, by which time it is fixed.
## Both are witnessable crimes through the one evidence-gated path.
class_name StreetCrime
extends RefCounted

const MUG_REACH_M := 3.0
const BRAVE_SHARE := 0.12
## method -> [seconds of work, how loud (witness severity x), uses the theft skill]
const WAYS_IN := {
	"pick": [14.0, 1.0, true], "kick": [4.0, 1.6, false], "window": [2.5, 1.9, false], "walk": [1.5, 0.8, false],
}
const LOOT_MIN := 15
const LOOT_MAX := 140
const RESTOCK_DAYS := 3.0
const HOUSE_ITEMS: Array[StringName] = [&"chips", &"water", &"bandage", &"knife", &"soda"]

static func mug(world: World, me: NPCData, state: PlayerStateData, victim: NPCData) -> Dictionary:
	if state.weapon == &"fists" or not state.aiming:
		return {"ok": false, "reason": "need_weapon_up"}
	if victim.position.distance_to(me.position) > MUG_REACH_M:
		return {"ok": false, "reason": "too_far"}
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.ARMED_ROBBERY])
	var brave: bool = state.weapon != &"pistol" and not Traits.has(state, &"killer") and world.runtime_rng.randf() < BRAVE_SHARE
	var schedule := world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if schedule != null:
		schedule.flee(victim)
	if brave:
		return {"ok": false, "reason": "victim_ran"}
	var take := victim.cash
	victim.cash = 0
	Wallet.earn_dirty(world, take)
	Skills.train(world, state, &"theft", 4.0)
	return {"ok": true, "effect": "mugged", "amount": take}

## Enter at a house door: starts the break-in (or says why not).
static func start_burglary(world: World, me: NPCData, state: PlayerStateData, house_id: StringName, way: String = "pick") -> Dictionary:
	var house: BuildingData = world.entities[house_id].get_component(ComponentNames.BUILDING)
	if house_id == me.home_building_id:
		return {"ok": false, "reason": "own_home"}
	fix_up(world, house)
	if world.tick - house.looted_tick < int(RESTOCK_DAYS * SimClock.day_ticks):
		return {"ok": false, "reason": "already_cleaned_out"}
	if way == "window" and house.windows_boarded:
		return {"ok": false, "reason": "boarded"}
	var w: Array = WAYS_IN[way]
	var secs: float = w[0] * (Skills.less(state, &"theft") if w[2] else 1.0)
	state.burglary_id = house_id
	state.burglary_done_tick = world.tick + int(secs * SimClock.TICKS_PER_SECOND)
	if way == "kick":
		house.door_kicked = true
	elif way == "window":
		house.windows_broken += 1
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.BURGLARY] * w[1])
	return {"ok": true, "effect": "breaking_in"}

## The ways in open at this house right now, for the E menu: [way, label].
static func ways_in(house: BuildingData) -> Array:
	if house.door_kicked or house.windows_broken > 0:
		return [["walk", "Go in (it's already broken)"]]
	var out: Array = [["pick", "Pick the lock (quiet, slow)"], ["kick", "Kick the door in (loud)"]]
	if not house.windows_boarded:
		out.append(["window", "Smash a window (loudest, quick)"])
	return out

## A burgled place gets its door and glass fixed by the time it is worth robbing again.
static func fix_up(world: World, house: BuildingData) -> void:
	if world.tick - house.looted_tick >= int(RESTOCK_DAYS * SimClock.day_ticks):
		house.door_kicked = false
		house.windows_broken = 0

## Each tick: the break-in finishes if you stayed at the door.
static func advance_burglary(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	if state.burglary_id == &"":
		return {}
	var house: BuildingData = world.entities[state.burglary_id].get_component(ComponentNames.BUILDING)
	if house.position.distance_to(me.position) > CrimeSystem.INTERACT_RADIUS * 1.5:
		state.burglary_id = &""
		return {"ok": false, "reason": "burglary_abandoned"}
	if world.tick < state.burglary_done_tick:
		return {}
	var house_id := state.burglary_id
	state.burglary_id = &""
	house.looted_tick = world.tick
	var cash := world.runtime_rng.randi_range(LOOT_MIN, LOOT_MAX)
	Wallet.earn_dirty(world, cash)
	var item: StringName = HOUSE_ITEMS[world.runtime_rng.randi() % HOUSE_ITEMS.size()]
	if BagGrid.room_for(state, item) > 0:   # INV1: a full bag leaves the item behind; the cash still comes
		state.inventory[item] = state.inventory.get(item, 0) + 1
		BagGrid.sync(state)
	else:
		item = &""
	Skills.train(world, state, &"theft", 8.0)
	_someone_home(world, house_id, me.position)
	return {"ok": true, "effect": "burgled", "amount": cash, "item": item}

## Whoever lives there and is in sees you up close: a sure report.
static func _someone_home(world: World, house_id: StringName, at: Vector2) -> void:
	for entity in world.get_entities_with_component(ComponentNames.NPC).values():
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc.home_building_id == house_id and npc.indoors and not npc.is_down and not entity.has_component(ComponentNames.PLAYER_STATE):
			npc.recognition_chance = 1.0
			CrimeSystem._report(world, npc, {"position": at, "severity": CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.BURGLARY], "tick": world.tick, "witness_id": npc.id})
			return
