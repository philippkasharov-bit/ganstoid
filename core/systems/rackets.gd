## BZ5: two more rackets.
## Fake money: a printing press (a dealer sells one) and paper and ink (a
## hardware counter) at home: each pack of paper prints BILLS_PER_PAPER
## fake hundreds. Their grade (Monopoly money to Superbill) comes from the
## forgery skill and a little luck. Spend them two ways:
##   at a shop counter: break a fake hundred on something small and walk out
##     with real change (clean), PASS_PER_DAY times a shop a day; the worse
##     the bill, the likelier the clerk holds it to the light: then it's
##     gone, the store won't serve you and the police get a call
##   to a dealer or fence: FENCE_SHARE of face for each, dirty, no risk
## Chop shop: park a car you stole by a chop shop and sell it (E at the
## counter): cash for the parts, and the car (the evidence) is gone.
class_name Rackets
extends RefCounted

const BILLS_PER_PAPER := 5
const FACE := 100
const CHANGE := 92              # what a broken fake hundred brings back, real
const PASS_PER_DAY := 2
const FENCE_SHARE := 0.25
const CAUGHT_SEVERITY := 0.3
const CHOP_R := 15.0            # the car must be parked this close to the chop shop
const CHOP_BASE := Vector2(250, 900)

## The chance a clerk spots a bill of this grade.
static func spot_chance(q: float) -> float:
	return clampf((4.6 - q) * 0.15, 0.03, 0.6)

## Print every pack of paper in the bag (needs the press at home).
static func print_money(world: World, state: PlayerStateData) -> Dictionary:
	if not state.lab.get("printer", false):
		return {"ok": false, "reason": "lab_need_gear"}
	var paper: int = state.inventory.get(&"ink_paper", 0)
	if paper <= 0:
		return {"ok": false, "reason": "lab_no_chems"}
	state.inventory.erase(&"ink_paper")
	var q := clampf(2.2 + 0.2 * Skills.level(state, &"forgery") + world.runtime_rng.randf_range(-0.4, 0.4), 1.0, 5.0)
	DrugLabSystem.add_drug(state, &"fake_bill", paper * BILLS_PER_PAPER, q)
	Skills.train(world, state, &"forgery", 5.0 * paper)
	return {"ok": true, "effect": "fake_printed", "amount": paper * BILLS_PER_PAPER}

## Break a fake hundred at a shop counter.
static func pass_bill(world: World, me: NPCData, state: PlayerStateData, shop_id: StringName) -> Dictionary:
	if int(state.inventory.get(&"fake_bill", 0)) <= 0:
		return {"ok": false, "reason": "nothing_to_sell"}
	var day := HustleSystem.day_of(world.tick)
	var key := "%s|%d" % [shop_id, day]
	if int(state.passed.get(key, 0)) >= PASS_PER_DAY:
		return {"ok": false, "reason": "fake_too_many"}
	state.passed[key] = int(state.passed.get(key, 0)) + 1
	state.inventory[&"fake_bill"] = int(state.inventory[&"fake_bill"]) - 1
	if int(state.inventory[&"fake_bill"]) <= 0:
		state.inventory.erase(&"fake_bill")
	if world.runtime_rng.randf() < spot_chance(DrugLabSystem.stars(state, &"fake_bill")):
		MemorySystem.remember(world, state, shop_id, "store_robbed")   # they won't serve you again
		world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {"position": me.position, "severity": CAUGHT_SEVERITY, "tick": world.tick, "witness_id": &""})
		return {"ok": false, "reason": "fake_spotted"}
	Wallet.earn_clean(world, CHANGE)
	return {"ok": true, "effect": "fake_passed", "amount": CHANGE}

## Sell every fake bill to a dealer.
static func sell_fakes(world: World, state: PlayerStateData) -> Dictionary:
	var n: int = state.inventory.get(&"fake_bill", 0)
	if n <= 0:
		return {"ok": false, "reason": "nothing_to_sell"}
	var each := roundi(FACE * FENCE_SHARE * clampf(DrugLabSystem.stars(state, &"fake_bill") / 3.0, 0.3, 1.6))
	state.inventory.erase(&"fake_bill")
	Wallet.earn_dirty(world, n * each)
	return {"ok": true, "effect": "fenced", "amount": n * each}

## A stolen car parked by this chop shop (the nearest, not yours), or null.
static func chop_car(world: World, shop: BuildingData) -> VehicleData:
	var best: VehicleData = null
	for id in world.spatial_index.query_nearby(shop.position):
		var e: Entity = world.entities.get(id)
		var c: VehicleData = e.get_component(ComponentNames.VEHICLE) if e != null else null
		if c == null or not c.touched or c.owner_id == PlayerFactory.PLAYER_ENTITY_ID or c.driver_id != &"" and c.driver_id != PlayerFactory.PLAYER_ENTITY_ID:
			continue
		if c.position.distance_to(shop.position) <= CHOP_R and (best == null or c.position.distance_to(shop.position) < best.position.distance_to(shop.position)):
			best = c
	return best

## What the chop shop pays for it: the make (the same car always the same) less the dents.
static func chop_price(car: VehicleData) -> int:
	var make := float(hash(String(car.id) + "make") % 1000) / 999.0
	return roundi(lerpf(CHOP_BASE.x, CHOP_BASE.y, make) * (1.0 - 0.7 * car.damage))

## Sell it: cash, and the car is gone for good (taken off the street).
static func chop(world: World, state: PlayerStateData, shop: BuildingData) -> Dictionary:
	var car := chop_car(world, shop)
	if car == null:
		return {"ok": false, "reason": "no_car"}
	var pay := chop_price(car)
	if state.vehicle_id == car.id:
		state.vehicle_id = &""
	car.driver_id = &""
	car.speed = 0.0
	car.damage = 1.0
	car.position = Vector2(-100000.0, -100000.0)   # in pieces, out of the city
	world.reindex_position(car.id)
	Wallet.earn_dirty(world, pay)
	return {"ok": true, "effect": "car_chopped", "amount": pay}

## BZ5b: a pawn shop you own can run a stolen-goods ring (RING_COST, any
## money): every night thieves sell to it and it sells on (RING_TAKE dirty),
## and it buys your own loot at RING_SHARE, better than any fence. A flat you
## own (not your home) can be a gambling den (DEN_COST): dice all night,
## DEN_TAKE dirty, more on a poor block, and no rent from it while it runs.
## Both can be raided any night (a bouncer from StaffSystem halves it): shut,
## the night's money gone, your case grows, it makes the paper.
const RING_COST := 1500
const RING_TAKE := Vector2(120, 380)
const RING_SHARE := 0.7
const RING_RAID := 0.04
const DEN_COST := 1500
const DEN_TAKE := 280
const DEN_RAID := 0.07
const RAID_CASE := 15.0

static func open_ring(world: World, state: PlayerStateData, shop: BuildingData) -> Dictionary:
	if not BusinessSystem.owned_by_player(shop) or shop.trade != &"pawn shop" or state.rings.get(shop.id, {}).get("open", false):
		return {"ok": false, "reason": "venue_cant"}
	if world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC).cash < RING_COST:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, RING_COST)
	state.rings[shop.id] = {"open": true, "last": 0}
	return {"ok": true, "effect": "ring_opened", "amount": RING_COST}

static func ring_at(state: PlayerStateData, id: StringName) -> bool:
	return state.rings.get(id, {}).get("open", false)

static func open_den(world: World, state: PlayerStateData, id: StringName) -> Dictionary:
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if not state.properties.has(id) or id == me.home_building_id or state.dens.get(id, {}).get("open", false):
		return {"ok": false, "reason": "venue_cant"}
	if me.cash < DEN_COST:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, DEN_COST)
	state.dens[id] = {"open": true, "last": 0}
	return {"ok": true, "effect": "den_opened", "amount": DEN_COST}

static func den_at(state: PlayerStateData, id: StringName) -> bool:
	return state.dens.get(id, {}).get("open", false)

## A night of the rings and dens (VenueSystem.close_night calls this).
static func night(world: World, state: PlayerStateData) -> void:
	var rng := world.runtime_rng
	for book in [state.rings, state.dens]:
		var den: bool = book == state.dens
		for id in book.keys():
			var r: Dictionary = book[id]
			if not r.get("open", false) or EmpireSystem.closed(world, r):   # BZ7: robbed by a rival: nothing tonight
				continue
			var e: Entity = world.entities.get(id)
			var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
			if b == null:
				book.erase(id)
				continue
			var raid := (DEN_RAID if den else RING_RAID) * (0.5 if VenueSystem.has_bouncer(state, id) else 1.0) * FrontSystem.guard_mult(state)
			if rng.randf() < raid:
				r["open"] = false
				r["raided"] = int(r.get("raided", 0)) + 1
				r["last"] = 0
				state.case_evidence += RAID_CASE
				StampView.put(state, "RAIDED", "the police shut your %s" % ("dice den" if den else "fencing ring"), UiTheme.BAD)
				PhoneSystem.push(world, state, "Word on the street", "Cops hit your %s last night. It's shut." % ("den" if den else "ring"))
				StreetTalk._count(world, state, "den_raided", 0)
				continue
			var take := 0
			if den:
				var wealth := float(BlockEconomyData.block_at(world, b.position).get("wealth", 0.5))
				take = roundi(DEN_TAKE * (0.6 + 0.8 * (1.0 - wealth)) * rng.randf_range(0.7, 1.3))
			else:
				take = rng.randi_range(int(RING_TAKE.x), int(RING_TAKE.y))
			Wallet.earn_dirty(world, take)
			r["last"] = take

## B9: a fixer you know washes dirty money for a cut, off the books (no IRS,
## no business needed): up to WASH_DAY_CAP a day. The first way to clean
## money before you own anything.
const WASH_CUT := 0.3
const WASH_DAY_CAP := 1000

static func wash_left(world: World, state: PlayerStateData) -> int:
	return maxi(0, WASH_DAY_CAP - int(state.passed.get("wash|%d" % HustleSystem.day_of(world.tick), 0)))

static func fixer_wash(world: World, state: PlayerStateData) -> Dictionary:
	var amount := mini(state.dirty_cash, wash_left(world, state))
	if amount <= 0:
		return {"ok": false, "reason": "wash_none" if state.dirty_cash <= 0 else "wash_cap"}
	var key := "wash|%d" % HustleSystem.day_of(world.tick)
	state.passed[key] = int(state.passed.get(key, 0)) + amount
	var r := Wallet.launder(world, amount, WASH_CUT)
	return {"ok": true, "effect": "washed_fixer", "amount": int(r["washed"]) - int(r["fee"])}
