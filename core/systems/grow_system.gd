## BZ1: grow it yourself, by hand, at home. Gear comes from a hardware
## counter (tent, a shop light or a proper HPS lamp, a fan, a carbon filter,
## plant food); seeds come from a dealer. Set it up at your home door (E),
## plant, water at least every WATER_H game hours, feed, harvest after
## GROW_DAYS, let it dry DRY_H, bag it. Everything you bag has a quality,
## 1 to 5 stars (QL1), from the strain, your lamp, the fan, how well you kept
## the plants watered and fed, and your growing skill. The stars set the
## price (PRICE_BY_STARS), and good sales build your brand (the name stamped
## on your bags, 90s style) while bad ones sink it. Cutting stretches what
## you carry by half at a star's cost. The risk is the smell: each hour a
## plant may tip off a neighbour (a carbon filter cuts it to FILTER_KEEP),
## and the call goes on your case file. Nothing here is legal: it's 199x.
class_name GrowSystem
extends SystemBase

const EVERY := 60
const PHASE := 49
const GOOD_ID := &"weed"
const PLANTS_PER_TENT := 4
const TENTS_BY_CRIB := [1, 2, 3, 4]   # how many tents fit (CribSystem tiers)
const GROW_DAYS := 2.0
const WATER_H := 12.0          # thirsty after this long
const WILT_PER_H := 0.08       # care lost each thirsty hour
const DIE_H := 48.0            # dry this long: dead
const DRY_H := 12.0
const MAX_FEEDS := 2
const BASE_YIELD := 3
const PRICE_BY_STARS := [0.6, 1.0, 1.3, 1.7, 2.3]   # street weed (2 stars) sells as it always did
const SHOP_LIGHT_CAP := 3.0    # a plain shop light can't grow better than this
const SMELL_PER_PLANT_H := 0.01
const FILTER_KEEP := 0.15
const SMELL_SEVERITY := 0.15
const CUT_STRETCH := 0.5
const BRANDS := ["Blue Dragon", "Red Devil", "Black Widow", "Gold Crown", "White Tiger", "Green Monster", "Lucky 7", "Night Train"]
const BRAND_GOOD := 0.02       # brand name gained per good sale (4 stars and up)
const BRAND_BAD := 0.04        # lost per bad one (under 2 stars)
const BRAND_TALK := [0.3, 0.6, 0.9]   # word on the street at these
## QL3: seed item -> the strain: name, base quality, grow time and yield
## factors, how much it stinks, the high, and where it sells best (Grades.fit).
const STRAINS := {
	&"seeds_mids": {"name": "Street mids", "base": 2.0, "days": 1.0, "yield": 1.0, "smell": 1.0, "high": "mellow, nothing special", "sells": ""},
	&"seeds_skunk": {"name": "Skunk #1", "base": 2.6, "days": 1.0, "yield": 1.5, "smell": 2.0, "high": "strong, and it stinks", "sells": "poor"},
	&"seeds_nl": {"name": "Northern Lights", "base": 3.0, "days": 0.8, "yield": 1.0, "smell": 0.6, "high": "sleepy, smooth", "sells": "rich"},
	&"seeds_kush": {"name": "OG Kush", "base": 3.2, "days": 1.0, "yield": 0.9, "smell": 1.4, "high": "heavy body high", "sells": "poor"},
	&"seeds_blue": {"name": "Blueberry", "base": 3.5, "days": 1.1, "yield": 0.9, "smell": 0.8, "high": "sweet, easy", "sells": "rich"},
	&"seeds_haze": {"name": "Purple Haze", "base": 3.8, "days": 1.3, "yield": 0.9, "smell": 1.0, "high": "up, talky head high", "sells": "club"},
}
const SEED_ORDER: Array[StringName] = [&"seeds_haze", &"seeds_blue", &"seeds_kush", &"seeds_nl", &"seeds_skunk", &"seeds_mids"]
const GEAR := [&"grow_tent", &"shop_light", &"hps_lamp", &"grow_fan", &"carbon_filter"]

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _hour := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if not state.ui_grow.is_empty():
			var name := String(state.ui_grow.get("brand", "")).strip_edges().left(24)
			if name != "":
				state.brand = name
			state.ui_grow = {}
		var hour := tick / SimClock.hours(1.0)
		if hour != _hour:
			var first := _hour == -1
			_hour = hour
			if not first:
				tend_hour(_world, p.get_component(ComponentNames.NPC), state, tick)

## One game hour at the grow: thirsty plants wilt (and die), the smell may
## tip off a neighbour.
static func tend_hour(world: World, me: NPCData, state: PlayerStateData, tick: int) -> void:
	var gw := StaffSystem.grower(state)
	if not gw.is_empty():
		grower_hour(world, state, gw, tick)   # BZ2
	var plants: Array = state.grow.get("plants", [])
	var living := 0.0   # QL3: how much it stinks, strain by strain
	for pl in plants:
		if pl.get("dead", false):
			continue
		var dry_h := float(tick - int(pl["watered"])) / SimClock.hours(1.0)
		if dry_h >= DIE_H:
			pl["dead"] = true
		elif dry_h >= WATER_H:
			pl["care"] = maxf(0.0, float(pl["care"]) - WILT_PER_H)
			living += float(_strain(pl)["smell"])
		else:
			living += float(_strain(pl)["smell"])
	var chance := SMELL_PER_PLANT_H * living * (FILTER_KEEP if state.grow.get("filter", false) else 1.0)
	if living > 0.0 and world.runtime_rng.randf() < chance:
		var home: Entity = world.entities.get(me.home_building_id)
		var at: Vector2 = home.get_component(ComponentNames.BUILDING).position if home != null else me.position
		world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {"position": at, "severity": SMELL_SEVERITY, "tick": tick, "witness_id": &""})
		if not state.grow.get("smelled", false):
			state.grow["smelled"] = true
			PhoneSystem.push(world, state, "Your neighbour", "What is that SMELL? I'm calling somebody about it.")

## BZ2: an hour of your grower's work: water before they're thirsty, feed
## from the stock, harvest what's ripe, bag what's dry into the stash (less
## what a shifty one keeps), clear the dead and replant from the stock.
static func grower_hour(world: World, state: PlayerStateData, gw: Dictionary, tick: int) -> void:
	var stock: Dictionary = state.grow.get("stock", {})
	for pl in state.grow.get("plants", []):
		if pl.get("dead", false):
			continue
		if tick - int(pl["watered"]) >= SimClock.hours(WATER_H - 2.0):
			pl["watered"] = tick
		if int(pl["fed"]) < MAX_FEEDS and int(stock.get(&"plant_food", 0)) > 0:
			pl["fed"] = int(pl["fed"]) + 1
			stock[&"plant_food"] = int(stock[&"plant_food"]) - 1
	if state.grow.get("plants", []).any(func(pl: Dictionary) -> bool: return ripe(world, pl) or pl.get("dead", false)):
		harvest(world, state, false)
	var left: Array = []
	for d in state.grow.get("drying", []):
		if tick >= int(d["ready"]):
			var units := int(d["units"])
			var kept := StaffSystem.skim_of(gw, units)
			gw["skimmed"] = int(gw.get("skimmed", 0)) + kept
			_to_stash(state, units - kept, float(d["q"]), String(d["strain"]))
		else:
			left.append(d)
	state.grow["drying"] = left
	var plants: Array = state.grow.get("plants", [])
	for seed in SEED_ORDER:
		while int(stock.get(seed, 0)) > 0 and plants.size() < slots(state) and int(state.grow.get("lamp", 0)) > 0:
			plants.append({"strain": seed, "at": tick, "watered": tick, "fed": 0, "care": 1.0})
			stock[seed] = int(stock[seed]) - 1
	state.grow["plants"] = plants
	state.grow["stock"] = stock

static func _to_stash(state: PlayerStateData, units: int, q: float, strain: String) -> void:
	if units <= 0:
		return
	var st: Dictionary = state.grow.get("stash", {"units": 0, "q": q, "strain": strain})
	var had := int(st["units"])
	state.grow["stash"] = {"units": had + units, "q": (float(st["q"]) * had + q * units) / float(had + units), "strain": strain if had == 0 or String(st["strain"]) == strain else ""}

## BZ2: leave your seeds and plant food at the grow for the grower.
static func stock_up(_world: World, state: PlayerStateData) -> Dictionary:
	var stock: Dictionary = state.grow.get("stock", {})
	var n := 0
	for id in SEED_ORDER + [&"plant_food"]:
		var have := int(state.inventory.get(id, 0))
		if have > 0:
			stock[id] = int(stock.get(id, 0)) + have
			state.inventory.erase(id)
			n += have
	state.grow["stock"] = stock
	return {"ok": true, "effect": "grow_stocked", "amount": n} if n > 0 else {"ok": false, "reason": "grow_no_seeds"}

## BZ2: take the bags the grower put by.
static func pick_up(world: World, state: PlayerStateData) -> Dictionary:
	var st: Dictionary = state.grow.get("stash", {})
	var units := int(st.get("units", 0))
	if units <= 0:
		return {"ok": false, "reason": "grow_not_dry"}
	add_product(state, units, float(st["q"]), String(st["strain"]))
	state.grow.erase("stash")
	if state.brand == "":
		state.brand = BRANDS[world.runtime_rng.randi() % BRANDS.size()]
	return {"ok": true, "effect": "grow_bagged", "amount": units}

## Moves every piece of grow gear in the bag into the grow at home.
static func install(world: World, state: PlayerStateData) -> Dictionary:
	var g := state.grow
	var put := 0
	for id in GEAR:
		var n: int = state.inventory.get(id, 0)
		while n > 0:
			match id:
				&"grow_tent":
					if int(g.get("tents", 0)) >= tents_max(state):
						break
					g["tents"] = int(g.get("tents", 0)) + 1
				&"shop_light":
					if int(g.get("lamp", 0)) >= 1:
						break
					g["lamp"] = 1
				&"hps_lamp":
					if int(g.get("lamp", 0)) >= 2:
						break
					g["lamp"] = 2
				&"grow_fan":
					if g.get("fan", false):
						break
					g["fan"] = true
				&"carbon_filter":
					if g.get("filter", false):
						break
					g["filter"] = true
			n -= 1
			put += 1
		if n > 0:
			state.inventory[id] = n
		else:
			state.inventory.erase(id)
	state.grow = g
	if put == 0:
		return {"ok": false, "reason": "grow_no_gear"}
	return {"ok": true, "effect": "grow_setup", "amount": put}

static func tents_max(state: PlayerStateData) -> int:
	return TENTS_BY_CRIB[clampi(state.crib, 0, TENTS_BY_CRIB.size() - 1)]

static func slots(state: PlayerStateData) -> int:
	return int(state.grow.get("tents", 0)) * PLANTS_PER_TENT

## Plants seeds from the bag into free spots (best seeds first).
static func plant(world: World, state: PlayerStateData) -> Dictionary:
	if int(state.grow.get("tents", 0)) == 0 or int(state.grow.get("lamp", 0)) == 0:
		return {"ok": false, "reason": "grow_need_gear"}
	var plants: Array = state.grow.get("plants", [])
	var put := 0
	for seed in SEED_ORDER:
		while int(state.inventory.get(seed, 0)) > 0 and plants.size() < slots(state):
			plants.append({"strain": seed, "at": world.tick, "watered": world.tick, "fed": 0, "care": 1.0})
			state.inventory[seed] = int(state.inventory[seed]) - 1
			if state.inventory[seed] <= 0:
				state.inventory.erase(seed)
			put += 1
	state.grow["plants"] = plants
	if put == 0:
		return {"ok": false, "reason": "grow_no_seeds" if plants.size() < slots(state) else "grow_full"}
	return {"ok": true, "effect": "grow_planted", "amount": put}

static func water(world: World, state: PlayerStateData) -> Dictionary:
	var n := 0
	for pl in state.grow.get("plants", []):
		if not pl.get("dead", false):
			pl["watered"] = world.tick
			n += 1
	return {"ok": true, "effect": "grow_watered", "amount": n} if n > 0 else {"ok": false, "reason": "grow_nothing"}

static func feed(_world: World, state: PlayerStateData) -> Dictionary:
	var n := 0
	for pl in state.grow.get("plants", []):
		if not pl.get("dead", false) and int(pl["fed"]) < MAX_FEEDS and int(state.inventory.get(&"plant_food", 0)) > 0:
			pl["fed"] = int(pl["fed"]) + 1
			state.inventory[&"plant_food"] = int(state.inventory[&"plant_food"]) - 1
			n += 1
	if int(state.inventory.get(&"plant_food", 0)) <= 0:
		state.inventory.erase(&"plant_food")
	return {"ok": true, "effect": "grow_fed", "amount": n} if n > 0 else {"ok": false, "reason": "grow_no_food"}

static func ripe(world: World, pl: Dictionary) -> bool:
	var days: float = GROW_DAYS * float(_strain(pl)["days"])
	return not pl.get("dead", false) and world.tick - int(pl["at"]) >= int(days * SimClock.day_ticks)

static func thirsty(world: World, pl: Dictionary) -> bool:
	return not pl.get("dead", false) and world.tick - int(pl["watered"]) >= SimClock.hours(WATER_H)

## The stars a plant would give if cut now (1..5).
static func quality(state: PlayerStateData, pl: Dictionary) -> float:
	var lamp := int(state.grow.get("lamp", 0))
	var q: float = _strain(pl)["base"]
	q += 0.6 if lamp >= 2 else 0.0
	q += 0.3 if state.grow.get("fan", false) else 0.0
	q += 0.25 * int(pl["fed"])
	var gw := StaffSystem.grower(state)   # BZ2: a skilled grower counts as your own hand
	q += 0.08 * maxi(Skills.level(state, &"growing"), roundi(float(gw.get("skill", 0.0)) * Skills.MAX_LEVEL))
	q -= (1.0 - float(pl["care"])) * 2.0
	return clampf(q, 1.0, 5.0 if lamp >= 2 else SHOP_LIGHT_CAP)

static func yield_of(state: PlayerStateData, pl: Dictionary) -> int:
	return roundi((BASE_YIELD + (2 if int(state.grow.get("lamp", 0)) >= 2 else 0) + int(pl["fed"]) + (1 if float(pl["care"]) > 0.8 else 0)) * float(_strain(pl)["yield"]))

## A plant's strain (an unknown one reads as street mids).
static func _strain(pl: Dictionary) -> Dictionary:
	return STRAINS.get(StringName(pl.get("strain", &"")), STRAINS[&"seeds_mids"])

## Cuts every ripe plant (and clears the dead); they hang to dry.
static func harvest(world: World, state: PlayerStateData, by_hand := true) -> Dictionary:
	var keep: Array = []
	var drying: Array = state.grow.get("drying", [])
	var units := 0
	for pl in state.grow.get("plants", []):
		if pl.get("dead", false):
			continue
		if ripe(world, pl):
			var u := yield_of(state, pl)
			drying.append({"units": u, "q": quality(state, pl), "strain": String(pl["strain"]), "ready": world.tick + SimClock.hours(DRY_H)})
			units += u
		else:
			keep.append(pl)
	var cleared: int = (state.grow.get("plants", []) as Array).size() - keep.size()
	state.grow["plants"] = keep
	state.grow["drying"] = drying
	if units == 0:
		return {"ok": cleared > 0, "effect": "grow_cleared", "reason": "grow_not_ripe"} if cleared > 0 else {"ok": false, "reason": "grow_not_ripe"}
	if by_hand:
		Skills.train(world, state, &"growing", 6.0 * units)
	return {"ok": true, "effect": "grow_harvested", "amount": units}

## Bags what has dried: it joins what you carry, the stars averaged in.
static func bag(world: World, state: PlayerStateData) -> Dictionary:
	var left: Array = []
	var units := 0
	for d in state.grow.get("drying", []):
		if world.tick >= int(d["ready"]):
			add_product(state, int(d["units"]), float(d["q"]), String(d["strain"]))
			units += int(d["units"])
		else:
			left.append(d)
	state.grow["drying"] = left
	if units == 0:
		return {"ok": false, "reason": "grow_not_dry"}
	if state.brand == "":
		state.brand = BRANDS[world.runtime_rng.randi() % BRANDS.size()]
	return {"ok": true, "effect": "grow_bagged", "amount": units}

## Adds weed you carry; its stars average with what you had.
static func add_product(state: PlayerStateData, units: int, q: float, strain: String) -> void:
	var had: int = state.inventory.get(GOOD_ID, 0)
	var old_q := stars_carried(state)
	state.inventory[GOOD_ID] = had + units
	var same: bool = had == 0 or String(state.product.get("strain", "")) == strain
	state.product = {"q": (old_q * had + q * units) / float(had + units), "strain": strain if same else ""}   # QL3: mixed strains lose their name

## The stars of the weed you carry (bought on the street: 2).
static func stars_carried(state: PlayerStateData) -> float:
	var q: Variant = state.product.get("q", 2.0)
	return clampf(float(q), 1.0, 5.0) if typeof(q) in [TYPE_FLOAT, TYPE_INT] else 2.0

## Stretch what you carry by half; a star off.
static func cut(_world: World, state: PlayerStateData) -> Dictionary:
	var had: int = state.inventory.get(GOOD_ID, 0)
	if had < 2:
		return {"ok": false, "reason": "nothing_to_sell"}
	var more := ceili(had * CUT_STRETCH)
	state.inventory[GOOD_ID] = had + more
	state.product["q"] = maxf(1.0, stars_carried(state) - 1.0)
	return {"ok": true, "effect": "grow_cut", "amount": more}

## What a sale of what you carry fetches, times this (stars and brand).
static func price_mult(state: PlayerStateData) -> float:
	var s := clampi(roundi(stars_carried(state)), 1, 5)
	return PRICE_BY_STARS[s - 1] * (1.0 + 0.4 * clampf(state.brand_rep, 0.0, 1.0))

## A sale went out: the brand's name goes up or down with the stars.
static func sold(world: World, state: PlayerStateData) -> void:
	if state.brand == "":
		return
	var before := state.brand_rep
	var s := stars_carried(state)
	if s >= 4.0:
		state.brand_rep = minf(1.0, state.brand_rep + BRAND_GOOD)
	elif s < 2.0:
		state.brand_rep = maxf(0.0, state.brand_rep - BRAND_BAD)
	for at in BRAND_TALK:
		if before < at and state.brand_rep >= at:
			PhoneSystem.push(world, state, "Word on the street", "People are asking for '%s' by name." % state.brand)

## QL3: the weed's grade in words ("Chronic (4.6)").
static func stars_text(q: float) -> String:
	return Grades.drug_text(&"weed", q)

## The next thing the grow needs, for the pager ("" when nothing).
static func need_line(world: World, state: PlayerStateData) -> String:
	if not StaffSystem.grower(state).is_empty():   # BZ2: the grower handles the plants
		var waiting := int(state.grow.get("stash", {}).get("units", 0))
		return "Your grower put %d bags by: pick them up at home" % waiting if waiting >= 10 else ""
	var plants: Array = state.grow.get("plants", [])
	var dry := 0
	var ready := 0
	for pl in plants:
		dry += 1 if thirsty(world, pl) else 0
		ready += 1 if ripe(world, pl) else 0
	if dry > 0:
		return "%d plant%s need water: go home, E > Water the plants" % [dry, "" if dry == 1 else "s"]
	if ready > 0:
		return "Your plants are ready: go home, E > Harvest"
	for d in state.grow.get("drying", []):
		if world.tick >= int(d["ready"]):
			return "Your weed has dried: go home, E > Bag it"
	return ""
