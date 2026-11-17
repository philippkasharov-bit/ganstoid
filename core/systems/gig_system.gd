## RP2: a straight life on the side (RP-server style), all through the phone's
## Jobs and Property apps:
##   GIGS      three legal gigs a day, clean pay:
##             delivery  pick up at a shop, drop at an address before the time
##             taxi      a fare from A to B (needs a car and a licence)
##             security  stand watch at a building through the night
##   LICENCE   a driving licence ($150). Drive without one where a cop can see
##             you and it goes on your case.
##   PROPERTY  buy homes and flats (price by how well off the block is). Move
##             into one, or let them out: rent comes in clean every morning.
## Phone buttons ask (ui_gig); this system does it. Saved: gig, gigs, licence, properties.
class_name GigSystem
extends SystemBase

const PHASE := 53
const PER_DAY := 3
const LICENCE_COST := 150
const NO_LICENCE_EVIDENCE := 4.0
const NO_LICENCE_EVERY_S := 120.0
const AT_M := 6.0
const SECURITY_M := 30.0
const SECURITY_HOURS := [22.0, 2.0]
const KINDS := {
	"delivery": ["Delivery run", 70, 1.5],      # [name, base pay, hours to do it]
	"taxi": ["Taxi fare", 90, 1.0],
	"security": ["Night security", 160, 0.0],
}
const RENT_SHARE := 0.006                    # of the price, per day
const LISTINGS := 3

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _warned_tick := -1000000

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if not state.ui_gig.is_empty():
			var ask := state.ui_gig
			state.ui_gig = {}
			StreetTalk.say(_world, state, handle(_world, state, me, ask, tick))
		if tick % SimClock.TICKS_PER_SECOND != PHASE:
			continue
		var day := HustleSystem.day_of(tick)
		if state.gig_day != day:
			state.gig_day = day
			roll(_world, state, me, day)
			_rent(state)
		if not state.gig.is_empty():
			advance(_world, state, me, tick)
		_licence_check(state, me, tick)

## Today's three gigs, near you (seeded by the day).
static func roll(world: World, state: PlayerStateData, me: NPCData, day: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("gigs" + str(day))
	state.gigs = []
	var shops: Array = []
	var homes: Array = []
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		var d := b.position.distance_to(me.position)
		if d > 800.0:
			continue
		if ShopSystem.counter_kind(world, b.id) == "shop":
			shops.append(b.position)
		elif b.building_type == GanstoidEnums.BuildingType.RESIDENCE:
			homes.append(b.position)
	if shops.is_empty() or homes.size() < 2:
		return
	shops.sort()
	homes.sort()
	for kind in ["delivery", "taxi", "security"]:
		var a: Vector2 = shops[rng.randi() % shops.size()] if kind != "taxi" else homes[rng.randi() % homes.size()]
		var b: Vector2 = homes[rng.randi() % homes.size()]
		var pay := int(KINDS[kind][1] + (a.distance_to(b) / 10.0 if kind != "security" else 0.0))
		state.gigs.append({"kind": kind, "from": a, "to": b if kind != "security" else a, "pay": pay})

func handle(world: World, state: PlayerStateData, me: NPCData, ask: Dictionary, tick: int) -> Dictionary:
	if ask.has("take"):
		return take(world, state, int(ask["take"]), tick)
	if ask.has("licence"):
		return buy_licence(world, state)
	if ask.has("buy"):
		return buy_property(world, state, StringName(ask["buy"]))
	if ask.has("move"):
		return move_in(world, state, me, StringName(ask["move"]))
	return {}

static func take(world: World, state: PlayerStateData, i: int, tick: int) -> Dictionary:
	if not state.gig.is_empty() or i < 0 or i >= state.gigs.size():
		return {"ok": false, "reason": "gig_busy"}
	var g: Dictionary = state.gigs[i].duplicate()
	if g["kind"] == "taxi" and (not state.licence or state.vehicle_id == &""):
		return {"ok": false, "reason": "gig_need_car"}
	g["stage"] = "pickup" if g["kind"] != "security" else "wait"
	g["until"] = tick + SimClock.hours(float(KINDS[g["kind"]][2]) if g["kind"] != "security" else 12.0)
	g["watched"] = 0.0
	state.gig = g
	state.gigs.remove_at(i)
	state.waypoint = g["from"]
	return {"ok": true, "effect": "gig_taken"}

## A step of the gig you are on.
static func advance(world: World, state: PlayerStateData, me: NPCData, tick: int) -> void:
	var g := state.gig
	var name: String = KINDS[g["kind"]][0]
	if tick > int(g["until"]) and g["stage"] != "wait":
		PhoneSystem.push(world, state, name, "Too slow. The gig went to someone else.")
		state.gig = {}
		return
	match String(g["kind"]):
		"delivery", "taxi":
			if g["stage"] == "pickup" and me.position.distance_to(g["from"]) <= AT_M + (8.0 if g["kind"] == "taxi" else 0.0):
				g["stage"] = "dropoff"
				state.waypoint = g["to"]
				PhoneSystem.push(world, state, name, "Got it. Now to the address on your GPS.")
			elif g["stage"] == "dropoff" and me.position.distance_to(g["to"]) <= AT_M + (8.0 if g["kind"] == "taxi" else 0.0):
				if g["kind"] == "taxi" and state.vehicle_id == &"":
					return
				_paid(world, state, g)
		"security":
			var hour := SimClock.day_fraction(tick) * 24.0
			var on_shift: bool = hour >= SECURITY_HOURS[0] or hour < SECURITY_HOURS[1]
			if on_shift and me.position.distance_to(g["from"]) <= SECURITY_M:
				g["stage"] = "watch"
				g["watched"] = float(g["watched"]) + 1.0 / (SimClock.day_ticks / 24.0 / SimClock.TICKS_PER_SECOND)   # game hours watched
				if float(g["watched"]) >= 4.0:
					_paid(world, state, g)
			elif g["stage"] == "watch" and not on_shift:
				PhoneSystem.push(world, state, name, "You left the post. No pay.")
				state.gig = {}

static func _paid(world: World, state: PlayerStateData, g: Dictionary) -> void:
	Wallet.earn_clean(world, int(g["pay"]))
	StampView.put(state, "GIG DONE", "+$%d clean" % int(g["pay"]), UiTheme.GOOD)
	if state.waypoint != Vector2.INF and (state.waypoint.distance_to(g["to"]) < 1.0 or state.waypoint.distance_to(g["from"]) < 1.0):
		state.waypoint = Vector2.INF
	state.gig = {}

static func buy_licence(world: World, state: PlayerStateData) -> Dictionary:
	if state.licence:
		return {"ok": false, "reason": "licence_have"}
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if me.cash < LICENCE_COST:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, LICENCE_COST)
	state.licence = true
	return {"ok": true, "effect": "licence_bought", "amount": LICENCE_COST}

## Driving with no licence where a cop sees you goes on your case (not too often).
func _licence_check(state: PlayerStateData, me: NPCData, tick: int) -> void:
	if state.licence or state.vehicle_id == &"" or tick - _warned_tick < int(NO_LICENCE_EVERY_S * SimClock.TICKS_PER_SECOND):
		return
	for id in _world.spatial_index.query_nearby(me.position):
		var e: Entity = _world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and n.is_cop and not n.is_down and CrimeSystem.can_see(_world, n.position, me.position):
			_warned_tick = tick
			state.case_evidence += NO_LICENCE_EVIDENCE
			StreetTalk.say_key(_world, state, "no_licence")
			return

## Homes for sale near you: [building id, price] (cheapest on poor blocks).
static func listings(world: World, state: PlayerStateData, me: NPCData) -> Array:
	var out: Array = []
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.building_type != GanstoidEnums.BuildingType.RESIDENCE or b.id == me.home_building_id or state.properties.has(b.id):
			continue
		var d := b.position.distance_to(me.position)
		if d < 600.0:
			out.append([b.id, price(world, b), d])
	out.sort_custom(func(a: Array, c: Array) -> bool: return a[2] < c[2])
	return out.slice(0, LISTINGS)

static func price(world: World, b: BuildingData) -> int:
	var wealth: float = BuildingMesh3D.wealth_at(b.position) if BuildingMesh3D.wealth_by_cell.size() > 0 else 0.5
	return int(round((3000.0 + 12000.0 * clampf(wealth, 0.0, 1.0)) / 100.0) * 100.0)

static func buy_property(world: World, state: PlayerStateData, id: StringName) -> Dictionary:
	var e: Entity = world.entities.get(id)
	var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
	if b == null or b.building_type != GanstoidEnums.BuildingType.RESIDENCE or state.properties.has(id):
		return {"ok": false, "reason": "not_for_sale"}
	var cost := price(world, b)
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if me.cash - state.dirty_cash < cost:
		return {"ok": false, "reason": "need_clean_cash"}
	Wallet.spend(world, cost)
	state.properties.append(id)
	state.property_prices[id] = cost
	b.touched = true
	return {"ok": true, "effect": "property_bought", "amount": cost}

static func move_in(world: World, state: PlayerStateData, me: NPCData, id: StringName) -> Dictionary:
	if not state.properties.has(id):
		return {"ok": false, "reason": "not_yours"}
	me.home_building_id = id
	return {"ok": true, "effect": "moved_in"}

func _rent(state: PlayerStateData) -> void:
	var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var total := 0
	for id in state.properties:
		if id != me.home_building_id and not Rackets.den_at(state, id):   # BZ5b: a den pays at night instead
			total += int(float(state.property_prices.get(id, 5000)) * RENT_SHARE)
	if total > 0:
		Wallet.earn_clean(_world, total)
		PhoneSystem.push(_world, state, "Tenants", "Rent's in: $%d." % total)

static func line(world: World, state: PlayerStateData) -> String:
	var g := state.gig
	if g.is_empty():
		return ""
	var name: String = KINDS[g["kind"]][0]
	match String(g["stage"]):
		"pickup":
			return "%s: go to the pickup on your GPS" % name
		"dropoff":
			return "%s: drop off at the address on your GPS ($%d)" % [name, int(g["pay"])]
		"wait":
			return "%s: be at the building 22:00-02:00, stay 4 hours ($%d)" % [name, int(g["pay"])]
		"watch":
			return "%s: keep watch (%d of 4 hours)" % [name, int(float(g["watched"]))]
	return ""
