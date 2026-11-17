## BZ4: the drug chain beyond weed, made or brought in by you.
##   pills   a pill press at home (from a dealer) turns pill powder into
##           PILLS_PER_POWDER pills each, a press at a time
##   meth    lab glassware (a hardware counter) and boxes of cold medicine
##           (a dealer): the cook is a hands-on minute (CookWindow): the
##           heat creeps up; keep it in the green with Heat and Cool. The
##           longer in the green, the more stars; past the red line it
##           catches fire: batch gone, you get burned, the neighbours see
##           the smoke
##   imports from Soldier rank, a connect on the phone sells a shipment
##           (cash up front); it waits at a warehouse the next night for
##           PICKUP_H hours (the GPS points there). Some are a sting: the
##           police are waiting, it's all gone and your case grows
## Every drug carries stars (QL1) that set its price; coke and heroin can be
## stepped on (cut) like weed. 1990s rule: none of it is legal.
class_name DrugLabSystem
extends SystemBase

const PILLS_PER_POWDER := 3
const COOK_S := 20.0             # a cook lasts this many real seconds
const COOK_DRIFT := 0.035        # heat creeps up this much a second
const COOK_JITTER := 0.05
const COOK_STEP := 0.08          # one press of Heat or Cool
const GREEN := Vector2(0.55, 0.75)
const FIRE_AT := 0.95
const METH_PER_BOX := 2
const BURN := 0.2
const FIRE_SEVERITY := 0.3
const PICKUP_H := 6.0
const STING_CHANCE := 0.12
const STING_CASE := 25.0
const IMPORT_STARS := 4.0
const IMPORT_RANK := 2
## good -> [units, price $ up front]
const IMPORTS := {&"coke": [20, 1300], &"heroin": [15, 1150], &"guns": [6, 1800]}   # BZ5b: a crate of pistols to sell to the gangs
const CUTTABLE := [&"coke", &"heroin"]

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if not state.ui_lab.is_empty():
			var ask := state.ui_lab
			state.ui_lab = {}
			if ask.has("order"):
				StreetTalk.say(_world, state, order(_world, me, state, ask["order"]))
			elif ask.has("heat"):
				nudge(state, float(ask["heat"]))
			elif ask.has("price"):
				set_price(state, ask["price"], int(ask.get("set", 0)))
		if not state.cook.is_empty():
			cook_step(_world, me, state, 1.0 / SimClock.TICKS_PER_SECOND)
		if tick % 60 == 17 and not state.shipment.is_empty() and tick > int(state.shipment.get("until", 0)):
			state.shipment = {}
			state.waypoint = Vector2.INF
			PhoneSystem.push(_world, state, "The connect", "You never showed. That load's gone, and so is my patience.")

## Stars of a drug you carry (street stuff: 2).
static func stars(state: PlayerStateData, good: StringName) -> float:
	if good == GrowSystem.GOOD_ID:
		return GrowSystem.stars_carried(state)
	var q: Variant = state.products.get(good, 2.0)
	return clampf(float(q), 1.0, 5.0) if typeof(q) in [TYPE_FLOAT, TYPE_INT] else 2.0

static func price_mult(state: PlayerStateData, good: StringName) -> float:
	if good == GrowSystem.GOOD_ID:
		return GrowSystem.price_mult(state)
	return GrowSystem.PRICE_BY_STARS[clampi(roundi(stars(state, good)), 1, 5) - 1]

## Adds a drug you carry; its stars average with what you had.
static func add_drug(state: PlayerStateData, good: StringName, units: int, q: float) -> void:
	if good == GrowSystem.GOOD_ID:
		GrowSystem.add_product(state, units, q, "")
		return
	var had: int = state.inventory.get(good, 0)
	var old := stars(state, good)
	state.inventory[good] = had + units
	state.products[good] = (old * had + q * units) / float(had + units)

## Pills: every powder in the bag through the press.
static func press(world: World, state: PlayerStateData) -> Dictionary:
	if not state.lab.get("press", false):
		return {"ok": false, "reason": "lab_need_gear"}
	var kind := &"pill_powder" if state.inventory.has(&"pill_powder") else &"speed_powder"   # QL3: doves first
	var powder: int = state.inventory.get(kind, 0)
	if powder <= 0:
		return {"ok": false, "reason": "lab_no_chems"}
	state.inventory.erase(kind)
	var base: float = Grades.PILLS[kind]["base"]
	var q := clampf(base + 0.08 * Skills.level(state, &"chemistry") + world.runtime_rng.randf_range(-0.3, 0.3), 1.0, 4.5)
	var had_kind := String(state.products.get("pills_kind", ""))
	var carried: int = state.inventory.get(&"pills", 0)
	add_drug(state, &"pills", powder * PILLS_PER_POWDER, q)
	state.products["pills_kind"] = String(kind) if carried == 0 or had_kind == String(kind) else ""
	Skills.train(world, state, &"chemistry", 3.0 * powder)
	return {"ok": true, "effect": "lab_pressed", "amount": powder * PILLS_PER_POWDER}

## Moves press and glassware from the bag into the lab at home.
static func install(_world: World, state: PlayerStateData) -> Dictionary:
	var put := 0
	for id in [&"pill_press", &"lab_glass", &"print_press"]:
		var slot: String = {&"pill_press": "press", &"lab_glass": "glass", &"print_press": "printer"}[id]
		if state.inventory.has(id) and not state.lab.get(slot, false):
			state.lab[slot] = true
			state.inventory[id] = int(state.inventory[id]) - 1
			if int(state.inventory[id]) <= 0:
				state.inventory.erase(id)
			put += 1
	return {"ok": true, "effect": "grow_setup", "amount": put} if put > 0 else {"ok": false, "reason": "grow_no_gear"}

## Starts a cook with every box of cold medicine in the bag.
static func start_cook(_world: World, state: PlayerStateData) -> Dictionary:
	if not state.lab.get("glass", false):
		return {"ok": false, "reason": "lab_need_gear"}
	var boxes: int = state.inventory.get(&"cold_meds", 0)
	if boxes <= 0:
		return {"ok": false, "reason": "lab_no_chems"}
	state.inventory.erase(&"cold_meds")
	state.cook = {"heat": 0.4, "t": 0.0, "green": 0.0, "boxes": boxes}
	return {"ok": true, "effect": "lab_cooking"}

static func nudge(state: PlayerStateData, dir: float) -> void:
	if not state.cook.is_empty():
		state.cook["heat"] = clampf(float(state.cook["heat"]) + COOK_STEP * signf(dir), 0.0, 1.0)

## One step of the cook: the heat creeps; in the green counts; the red line burns.
static func cook_step(world: World, me: NPCData, state: PlayerStateData, dt: float) -> void:
	var c := state.cook
	c["heat"] = clampf(float(c["heat"]) + (COOK_DRIFT + world.runtime_rng.randf_range(-COOK_JITTER, COOK_JITTER)) * dt * 1.0, 0.0, 1.0)
	c["t"] = float(c["t"]) + dt
	var h := float(c["heat"])
	if h >= GREEN.x and h <= GREEN.y:
		c["green"] = float(c["green"]) + dt
	if h >= FIRE_AT:
		state.cook = {}
		state.lab["fires"] = int(state.lab.get("fires", 0)) + 1
		me.health = maxf(0.05, me.health - BURN)
		world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {"position": me.position, "severity": FIRE_SEVERITY, "tick": world.tick, "witness_id": &""})
		StampView.put(state, "FIRE!", "the batch is gone, and you're burned", UiTheme.BAD)
		StreetTalk.say_key(world, state, "lab_fire")
		StreetTalk._count(world, state, "lab_fire", 0)   # the paper
		return
	if float(c["t"]) >= COOK_S:
		var share := float(c["green"]) / COOK_S
		var q := clampf(1.0 + 4.0 * share + 0.05 * Skills.level(state, &"chemistry"), 1.0, 5.0)
		var units := int(c["boxes"]) * METH_PER_BOX
		add_drug(state, &"meth", units, q)
		Skills.train(world, state, &"chemistry", 4.0 * int(c["boxes"]))
		state.cook = {}
		StampView.put(state, "COOKED", "%d bags of %s" % [units, Grades.drug_text(&"meth", q)], UiTheme.GOOD)

## The connect sells a shipment: cash now, a warehouse tomorrow night.
static func order(world: World, me: NPCData, state: PlayerStateData, good: StringName) -> Dictionary:
	if not IMPORTS.has(good) or state.rank < IMPORT_RANK or not state.shipment.is_empty():
		return {"ok": false, "reason": "lab_no_connect"}
	var price: int = IMPORTS[good][1]
	if me.cash < price:
		return {"ok": false, "reason": "cant_afford"}
	var spot := _warehouse(world, me.position)
	if spot == &"":
		return {"ok": false, "reason": "lab_no_connect"}
	Wallet.spend(world, price)
	var ready := (world.tick / SimClock.day_ticks + 1) * SimClock.day_ticks + SimClock.hours(22.0)
	state.shipment = {"good": good, "units": IMPORTS[good][0], "at": spot, "from": ready, "until": ready + SimClock.hours(PICKUP_H), "sting": world.runtime_rng.randf() < STING_CHANCE}
	state.waypoint = (world.entities[spot].get_component(ComponentNames.BUILDING) as BuildingData).position
	PhoneSystem.push(world, state, "The connect", "Tomorrow, 10 at night, the warehouse I marked. Six hours, then it's gone.")
	return {"ok": true, "effect": "lab_ordered", "amount": price}

static func _warehouse(world: World, near: Vector2) -> StringName:
	var best := &""
	var best_d := INF
	for b in BusinessSystem.all_buildings(world):
		if b.trade == &"warehouse" and b.position.distance_to(near) < best_d:
			best_d = b.position.distance_to(near)
			best = b.id
	return best

static func can_pick_up(world: World, state: PlayerStateData, building_id: StringName) -> bool:
	var s := state.shipment
	return not s.is_empty() and s.get("at", &"") == building_id and world.tick >= int(s["from"]) and world.tick <= int(s["until"])

## At the warehouse in the window: the load, or the police.
static func pick_up(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	var s := state.shipment
	state.shipment = {}
	state.waypoint = Vector2.INF
	if s.get("sting", false):
		state.case_evidence += STING_CASE
		var cops := world.find_system(CopAISystem) as CopAISystem
		if cops != null:
			for id in world.spatial_index.query_nearby(me.position):
				var e: Entity = world.entities.get(id)
				var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
				if n != null and n.is_cop and not n.is_down:
					cops.alert(id)
		StampView.put(state, "STING!", "it was the police: run", UiTheme.BAD)
		return {"ok": false, "reason": "lab_sting"}
	if s["good"] == &"guns":   # BZ5b: a crate of pistols
		state.inventory[&"pistol"] = int(state.inventory.get(&"pistol", 0)) + int(s["units"])
	else:
		add_drug(state, s["good"], int(s["units"]), IMPORT_STARS)
	return {"ok": true, "effect": "lab_picked_up", "amount": int(s["units"])}

## QL3: what a unit of what you carry is worth to a buyer here.
static func value_each(world: World, state: PlayerStateData, good: StringName, at: Vector2, in_club: bool) -> float:
	var item: EconomyItemData = world.economy_items.get(good)
	var market := float(item.current_price) if item != null else 20.0
	var wealth := float(BlockEconomyData.block_at(world, at).get("wealth", 0.5))
	return market * price_mult(state, good) * Grades.fit(state, good, wealth, in_club)

## Your asking price here (what it's worth if you set none).
static func ask_each(world: World, state: PlayerStateData, good: StringName, at: Vector2, in_club: bool) -> int:
	var set_to := int(state.prices.get(good, 0))
	return set_to if set_to > 0 else maxi(1, roundi(value_each(world, state, good, at, in_club)))

## The share of buyers who take it at that price: all of them at its worth
## or less, half at 1.5x, hardly anyone at 2x.
static func accept(ask: float, value: float) -> float:
	return clampf(2.0 - ask / maxf(value, 1.0), 0.05, 1.0)

## Sets your asking price ($ a unit); 0 goes back to what it's worth.
static func set_price(state: PlayerStateData, good: StringName, to: int) -> void:
	if to <= 0:
		state.prices.erase(good)
	else:
		state.prices[good] = mini(to, 9999)

## Step on it: half as much again, a star off.
static func cut(_world: World, state: PlayerStateData, good: StringName) -> Dictionary:
	var had: int = state.inventory.get(good, 0)
	if had < 2 or not CUTTABLE.has(good):
		return {"ok": false, "reason": "nothing_to_sell"}
	var more := ceili(had * GrowSystem.CUT_STRETCH)
	var q := maxf(1.0, stars(state, good) - 1.0)
	state.inventory[good] = had + more
	state.products[good] = q
	return {"ok": true, "effect": "grow_cut", "amount": more}
