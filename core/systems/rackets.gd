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
