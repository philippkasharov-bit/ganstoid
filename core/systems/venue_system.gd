## BZ3: nightlife. Any shop you own can be turned into a night spot (E at
## its door, a licence in clean money):
##   nightclub         music and drinks; the steady earner
##   gentlemen's club  dancers and drinks (suggestive, never explicit); more
##                     money, more attention from vice
##   card room         a licensed poker room (California has them); the
##                     table takes a cut of every pot
## Each one has stars (QL1): 1 + its fit-out (DECOR_COST, three steps) + a
## good manager (StaffSystem). The night pays at closing (CLOSE_H), more on
## a rich block and with more stars, in clean money, and a cash business
## washes VENUE_WASH times its takings of your dirty money (BusinessSystem).
## No bouncer and some nights there's a fight: the takings drop.
## A back room (illegal, dirty money to set up) runs dice and cards after
## hours: a lot more dirty money each night, and a chance vice raids it
## (less with a bouncer): the back room's take is seized, your case grows,
## the back room is shut and it makes the paper. It's 199x Los Angeles.
class_name VenueSystem
extends SystemBase

const EVERY := 60
const PHASE := 7
const CLOSE_H := 4.0
## kind -> [name, licence $, base takings a night, vice heat (raid chance a night with a back room)]
const KINDS := {
	"club": ["Nightclub", 2000, 300, 0.05],
	"strip": ["Gentlemen's club", 3500, 450, 0.09],
	"cards": ["Card room", 3000, 380, 0.07],
}
const DECOR_COST := [1500, 3000, 6000]
const BACK_ROOM_COST := 2000
const BACK_ROOM_SHARE := 0.8     # of the base takings, dirty, each night
const FIGHT_CHANCE := 0.25       # a night without a bouncer
const FIGHT_KEEP := 0.7
const BOUNCER_RAID_CUT := 0.03
const RAID_CASE := 15.0
const VENUE_WASH := 1.5
const PILLS_BASE := 8            # pills a night the door staff move, plus PILLS_PER_STAR a star
const PILLS_PER_STAR := 4
const PILL_RAID := 0.04          # a night with pills: vice may find them
const PILL_CASE := 10.0

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _night := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	var night := (tick - SimClock.hours(CLOSE_H)) / SimClock.day_ticks
	if night == _night:
		return
	var first := _night == -1
	_night = night
	if first:
		return
	for p in entities.values():
		close_night(_world, p.get_component(ComponentNames.PLAYER_STATE))

## E at the door of a shop you own: open it as a night spot.
static func convert(world: World, state: PlayerStateData, building_id: StringName, kind: String) -> Dictionary:
	var e: Entity = world.entities.get(building_id)
	var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
	if b == null or not BusinessSystem.owned_by_player(b) or not KINDS.has(kind) or state.venues.has(building_id):
		return {"ok": false, "reason": "venue_cant"}
	var fee: int = KINDS[kind][1]
	if Wallet.clean(world) < fee:
		return {"ok": false, "reason": "need_clean_cash"}
	Wallet.spend_clean(world, fee)
	state.venues[building_id] = {"kind": kind, "decor": 0, "back_room": false, "last": 0}
	StampView.put(state, String(KINDS[kind][0]).to_upper(), "opens tonight", UiTheme.GOOD)
	return {"ok": true, "effect": "venue_opened", "amount": fee}

static func decorate(world: World, state: PlayerStateData, building_id: StringName) -> Dictionary:
	var v: Dictionary = state.venues.get(building_id, {})
	if v.is_empty() or int(v["decor"]) >= DECOR_COST.size():
		return {"ok": false, "reason": "venue_cant"}
	var cost: int = DECOR_COST[int(v["decor"])]
	if world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC).cash < cost:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, cost)
	v["decor"] = int(v["decor"]) + 1
	return {"ok": true, "effect": "venue_decor", "amount": cost}

static func open_back_room(world: World, state: PlayerStateData, building_id: StringName) -> Dictionary:
	var v: Dictionary = state.venues.get(building_id, {})
	if v.is_empty() or v["back_room"]:
		return {"ok": false, "reason": "venue_cant"}
	if world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC).cash < BACK_ROOM_COST:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, BACK_ROOM_COST)
	v["back_room"] = true
	return {"ok": true, "effect": "venue_back_room", "amount": BACK_ROOM_COST}

## BZ4: leave every pill you carry with the door staff to sell.
static func stock_pills(_world: World, state: PlayerStateData, building_id: StringName) -> Dictionary:
	var v: Dictionary = state.venues.get(building_id, {})
	var n: int = state.inventory.get(&"pills", 0)
	if v.is_empty() or n <= 0:
		return {"ok": false, "reason": "nothing_to_sell"}
	state.inventory.erase(&"pills")
	v["pills"] = int(v.get("pills", 0)) + n
	return {"ok": true, "effect": "grow_stocked", "amount": n}

## 1 to 5: the fit-out, plus a good manager.
static func stars(state: PlayerStateData, building_id: StringName) -> int:
	var v: Dictionary = state.venues.get(building_id, {})
	var m := StaffSystem.manager_of(state, building_id)
	return clampi(1 + int(v.get("decor", 0)) + (1 if float(m.get("skill", 0.0)) >= 0.5 else 0), 1, 5)

static func has_bouncer(state: PlayerStateData, building_id: StringName) -> bool:
	for id in state.staff:
		var s: Dictionary = state.staff[id]
		if s.get("role", "") == "bouncer" and s.get("at", &"") == building_id:
			return true
	return false

## Closing time: each venue's night.
static func close_night(world: World, state: PlayerStateData) -> void:
	var rng := world.runtime_rng
	for id in state.venues.keys():
		var e: Entity = world.entities.get(id)
		var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
		if b == null or not BusinessSystem.owned_by_player(b):
			state.venues.erase(id)
			continue
		var v: Dictionary = state.venues[id]
		var spec: Array = KINDS[v["kind"]]
		var wealth := float(BlockEconomyData.block_at(world, b.position).get("wealth", 0.5))
		var take := float(spec[2]) * (0.5 + wealth) * (0.5 + 0.25 * stars(state, id)) * rng.randf_range(0.85, 1.15)
		var bouncer := has_bouncer(state, id)
		v["fight"] = false
		if not bouncer and rng.randf() < FIGHT_CHANCE:
			take *= FIGHT_KEEP
			v["fight"] = true
		var clean := StaffSystem.managed(state, id, roundi(take))
		Wallet.earn_clean(world, clean)
		v["last"] = clean
		v["back"] = 0
		v["sold"] = 0
		var pills := int(v.get("pills", 0))
		if pills > 0:   # BZ4: the door staff move your pills
			if rng.randf() < PILL_RAID:
				v["pills"] = 0
				state.case_evidence += PILL_CASE
				PhoneSystem.push(world, state, String(spec[0]), "Vice searched the door staff. They found the pills.")
			else:
				var n := mini(pills, PILLS_BASE + PILLS_PER_STAR * stars(state, id))
				var item: EconomyItemData = world.economy_items.get(&"pills")
				var each := (item.current_price if item != null else 40) * DrugLabSystem.price_mult(state, &"pills")
				Wallet.earn_dirty(world, roundi(n * each))
				v["pills"] = pills - n
				v["sold"] = n
		if v["back_room"]:
			if rng.randf() < maxf(0.0, float(spec[3]) - (BOUNCER_RAID_CUT if bouncer else 0.0)):
				v["back_room"] = false
				v["raided"] = int(v.get("raided", 0)) + 1
				state.case_evidence += RAID_CASE
				PhoneSystem.push(world, state, String(spec[0]), "Vice hit the back room last night. They took the table money and shut it down.")
				StampView.put(state, "RAIDED", "vice shut your back room", UiTheme.BAD)
				StreetTalk._count(world, state, "den_raided", 0)
			else:
				var dirty := roundi(float(spec[2]) * BACK_ROOM_SHARE * (0.5 + wealth) * rng.randf_range(0.7, 1.3))
				Wallet.earn_dirty(world, dirty)
				v["back"] = dirty

## How much dirty money your night spots can wash a day (BusinessSystem).
static func wash_capacity(state: PlayerStateData) -> int:
	var total := 0
	for id in state.venues:
		total += int(float(state.venues[id].get("last", 0)) * VENUE_WASH)
	return total
