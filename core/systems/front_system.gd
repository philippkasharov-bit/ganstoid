## BZ6: the legal side. Any shop you own (not a night spot) can be made
## into a front of a kind (E at its counter, clean money):
##   car wash        a cash business: washes the most dirty money
##   laundromat      the same, a bit less, cheaper
##   restaurant      the best takings, on a rich block most of all
##   trucking        your trucks carry the loads: imports are stings half as often
##   security firm   your guards: raids on your rings, dens and back rooms, and
##                   fights in your clubs, a third less often
## Every shop you own can be upgraded three times (UPGRADE_COST x its price
## step): takings up by UPGRADE_STEP each. Rivals of the same trade within
## RIVAL_R are shown on the phone: they already take customers in the city's
## money day (EconomyFlow sends people to the shops near them).
## Taxes: each WEEK_DAYS the city takes TAX of what your businesses paid
## you. If you washed more dirty money that week than they took in, the
## IRS may look (AUDIT_PER x the excess share): a fine of AUDIT_FINE of what
## you washed, no washing for FREEZE_DAYS, and it's on your file.
class_name FrontSystem
extends SystemBase

const EVERY := 60
const PHASE := 11
## kind -> [name, setup $, takings x, washing x (of its takings)]
const KINDS := {
	"car_wash": ["Car wash", 2500, 1.0, 3.0],
	"laundromat": ["Laundromat", 1800, 0.9, 2.5],
	"restaurant": ["Restaurant", 4000, 1.4, 1.0],
	"trucking": ["Trucking company", 6000, 1.2, 1.0],
	"security": ["Security firm", 5000, 1.2, 1.0],
}
const UPGRADE_COST := [2000, 4000, 8000]
const UPGRADE_STEP := 0.25
const RIVAL_R := 300.0
const WEEK_DAYS := 7
const TAX := 0.15
const AUDIT_PER := 0.6
const AUDIT_FINE := 0.3
const FREEZE_DAYS := 3
const AUDIT_CASE := 10.0
const TRUCK_STING := 0.5
const GUARD_CUT := 0.67

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _day := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	var day := HustleSystem.day_of(tick)
	if day == _day:
		return
	var first := _day == -1
	_day = day
	if first:
		return
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if day % WEEK_DAYS == 0:
			week_end(_world, state, day)

## E at the counter of a shop you own: make it a front.
static func convert(world: World, state: PlayerStateData, b: BuildingData, kind: String) -> Dictionary:
	if not BusinessSystem.owned_by_player(b) or not KINDS.has(kind) or state.fronts.has(b.id) or state.venues.has(b.id):
		return {"ok": false, "reason": "venue_cant"}
	var cost: int = KINDS[kind][1]
	if Wallet.clean(world) < cost:
		return {"ok": false, "reason": "need_clean_cash"}
	Wallet.spend_clean(world, cost)
	state.fronts[b.id] = kind
	StampView.put(state, String(KINDS[kind][0]).to_upper(), "open for business", UiTheme.GOOD)
	return {"ok": true, "effect": "front_opened", "amount": cost}

static func upgrade(world: World, state: PlayerStateData, b: BuildingData) -> Dictionary:
	var tier := int(state.upgrades.get(b.id, 0))
	if not BusinessSystem.owned_by_player(b) or tier >= UPGRADE_COST.size():
		return {"ok": false, "reason": "venue_cant"}
	var cost: int = UPGRADE_COST[tier]
	if Wallet.clean(world) < cost:
		return {"ok": false, "reason": "need_clean_cash"}
	Wallet.spend_clean(world, cost)
	state.upgrades[b.id] = tier + 1
	return {"ok": true, "effect": "front_upgraded", "amount": cost}

## Shops of the same trade nearby (not yours) that take your customers.
static func rivals(world: World, b: BuildingData) -> int:
	var n := 0
	for other in BusinessSystem.all_buildings(world):
		if other != b and other.trade == b.trade and other.status < 2 and not BusinessSystem.owned_by_player(other) and other.position.distance_to(b.position) <= RIVAL_R:
			n += 1
	return n

## What an owned shop's takings are multiplied by: its kind and upgrades.
static func takings_mult(world: World, state: PlayerStateData, b: BuildingData) -> float:
	var m := 1.0 + UPGRADE_STEP * int(state.upgrades.get(b.id, 0))
	var kind: String = state.fronts.get(b.id, "")
	if kind != "":
		m *= float(KINDS[kind][2])
		if kind == "restaurant":
			m *= 0.6 + 0.8 * float(BlockEconomyData.block_at(world, b.position).get("wealth", 0.5))
	return m

## The extra dirty money your fronts can wash a day (on top of their takings).
static func wash_bonus(world: World, state: PlayerStateData) -> int:
	var extra := 0
	for id in state.fronts:
		var e: Entity = world.entities.get(id)
		var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
		if b != null and BusinessSystem.owned_by_player(b):
			extra += int(b.daily_revenue * (float(KINDS[state.fronts[id]][3]) - 1.0))
	return extra

static func owns_kind(state: PlayerStateData, kind: String) -> bool:
	return state.fronts.values().has(kind)

## Imports: half as many stings with your own trucks.
static func sting_mult(state: PlayerStateData) -> float:
	return TRUCK_STING if owns_kind(state, "trucking") else 1.0

## Raids and fights: a third fewer with your own security firm.
static func guard_mult(state: PlayerStateData) -> float:
	return GUARD_CUT if owns_kind(state, "security") else 1.0

## Is washing frozen by an audit?
static func frozen(world: World, state: PlayerStateData) -> bool:
	return HustleSystem.day_of(world.tick) < int(state.books.get("frozen_until", -1))

## The audit odds for the week so far (the phone shows it).
static func audit_chance(state: PlayerStateData) -> float:
	var earned := float(state.books.get("earned", 0))
	var washed := float(state.books.get("washed", 0))
	if washed <= 0.0:
		return 0.0
	return clampf(AUDIT_PER * (washed - earned) / washed, 0.0, 0.9)

## Sunday: the tax, and maybe the IRS.
static func week_end(world: World, state: PlayerStateData, day: int) -> void:
	var earned := int(state.books.get("earned", 0))
	var washed := int(state.books.get("washed", 0))
	var tax := int(round(earned * TAX))
	if tax > 0:
		var pay := mini(tax, Wallet.clean(world))
		Wallet.spend_clean(world, pay)
		PhoneSystem.push(world, state, "City tax office", "Business tax for the week: $%d paid%s." % [pay, "" if pay == tax else " ($%d short: we'll be in touch)" % (tax - pay)])
		if pay < tax:
			washed += (tax - pay) * 4   # owing the city makes them look harder
	var odds := clampf(AUDIT_PER * (float(washed) - float(earned)) / maxf(float(washed), 1.0), 0.0, 0.9)
	if washed > 0 and world.runtime_rng.randf() < odds:
		var fine := int(round(washed * AUDIT_FINE))
		Wallet.spend_clean(world, mini(fine, Wallet.clean(world)))
		state.books["frozen_until"] = day + FREEZE_DAYS
		state.case_evidence += AUDIT_CASE
		StampView.put(state, "AUDITED", "the IRS fined you $%d" % fine, UiTheme.BAD)
		PhoneSystem.push(world, state, "IRS", "Your books don't add up. Fine: $%d. No more cash deposits for %d days." % [fine, FREEZE_DAYS])
		StreetTalk._count(world, state, "audited", fine)
	state.books["earned"] = 0
	state.books["washed"] = 0
