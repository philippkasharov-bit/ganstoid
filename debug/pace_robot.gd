## B9/F3: the pacing robot. A bot plays the first PACE_DAYS game days (default
## 14) on the test city the way a typical player might, through the real
## game rules, and measures the pace: when money milestones, ranks, the first
## arrest and the first business come, where the money came from, and cash
## each morning. It doesn't walk: it steps next to whoever or whatever it
## acts on. Needs are kept topped up (upkeep isn't what this measures).
## Its plan, checked every game hour:
##   broke (under BROKE)      mug someone nearby (at most every MUG_GAP_H hours)
##   evenings                 rob a shop if the case file is low
##   CLEAN_SHIFT a day        work a shift (clean money, as at any counter)
##   GROW_AT cash             set up a grow at home, plant, water, harvest, bag
##   carrying weed            sell it hand to hand, a few tries an hour
##   GROWER_AT cash           hire a grower, leave seeds
##   shop price in clean      buy the cheapest shop; WASH_AT clean: make it a car wash
## Run: $G --headless --path . -s debug/pace_robot.gd   (PACE_DAYS, PACE_SEED, PACE_POP: default 1500)
extends SceneTree

const BROKE := 300
const MUG_GAP_H := 2
const CLEAN_SHIFT := 4
const SHIFT_PAY := 15
const GROW_AT := 700
const GROWER_AT := 1500
const WASH_AT := 4000
const SELL_TRIES := 6
const GROW_KIT := {&"grow_tent": 1, &"shop_light": 1, &"grow_fan": 1, &"plant_food": 8, &"seeds_kush": 4}

var w: World
var me: NPCData
var state: PlayerStateData
var log_lines: Array = []
var marks := {}
var income := {"mugging": 0, "robbery": 0, "weed": 0, "shifts": 0, "businesses": 0}
var counts := {"muggings": 0, "robberies": 0, "weed_sold": 0, "arrests": 0, "trials": 0, "grow_harvests": 0}
var last_mug := -1000000
var robbed_day := -1
var shift_day := -1
var shop: BuildingData = null
var busy_until := 0

func _initialize() -> void:
	var days := int(OS.get_environment("PACE_DAYS")) if OS.get_environment("PACE_DAYS") != "" else 14
	var seed := int(OS.get_environment("PACE_SEED")) if OS.get_environment("PACE_SEED") != "" else 4242
	w = World.new()
	SystemRegistry.register_all(w)
	var pop := int(OS.get_environment("PACE_POP")) if OS.get_environment("PACE_POP") != "" else 1500
	TestWorlds.real_city(w, seed)   # the fast clock and the test district...
	w = World.new()   # ...then the city again with a realistic crowd
	SystemRegistry.register_all(w)
	WorldGenerator.generate_real_city_game(w, seed, TestWorlds.city(), TestWorlds.city().spawn, TestWorlds.DISTRICT_RADIUS, pop)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	me = p.get_component(ComponentNames.NPC)
	state = p.get_component(ComponentNames.PLAYER_STATE)
	state.inventory[&"knife"] = 1
	var hour := SimClock.hours(1.0)
	var prev_rank := state.rank
	var prev_prison := 0
	var prev_trial := false
	var cash_days: Array = []
	var t0 := Time.get_ticks_msec()
	for i in days * SimClock.day_ticks:
		w.step(1.0 / 60.0)
		if w.tick % hour != 0:
			continue
		me.hunger = 1.0
		me.thirst = 1.0
		me.fatigue = 1.0
		if state.rank != prev_rank:
			_mark("rank: " + RankSystem.NAMES[state.rank])
			prev_rank = state.rank
		if state.prison_until_tick > 0 and prev_prison == 0:
			counts["arrests"] += 1
			_mark("first time inside")
		prev_prison = state.prison_until_tick
		if not state.trial.is_empty() and not prev_trial:
			counts["trials"] += 1
			_mark("first trial date")
		prev_trial = not state.trial.is_empty()
		for m in [500, 2000, 10000, 50000]:
			if me.cash >= m:
				_mark("cash $%d" % m)
		if w.tick % SimClock.day_ticks == hour * 8:
			cash_days.append(me.cash)
			income["businesses"] += int(state.biz_day.get("shops", 0))   # one payout a day
			state.biz_day["shops"] = 0
		if state.prison_until_tick > 0 or me.is_down:
			continue
		_play()
	var real_s := (Time.get_ticks_msec() - t0) / 1000.0
	print("PACE: %d game days on seed %d in %.0f s" % [days, seed, real_s])
	print("PACE: milestones (game day.hour; at 1x a game day is an hour of real play)")
	for k in marks:
		print("  %-22s day %s" % [k, marks[k]])
	print("PACE: income  " + "  ".join(income.keys().map(func(k: String) -> String: return "%s $%d" % [k, income[k]])))
	print("PACE: counts  " + "  ".join(counts.keys().map(func(k: String) -> String: return "%s %d" % [k, counts[k]])))
	print("PACE: cash each morning " + str(cash_days))
	print("PACE: end cash $%d (dirty $%d), rank %s, case %d, places %d" % [me.cash, state.dirty_cash, RankSystem.NAMES[state.rank], int(state.case_evidence), EmpireSystem.places(w, state).size()])
	quit(0)

## One game hour of decisions.
func _play() -> void:
	var h := SimClock.day_fraction(w.tick) * 24.0
	var day := HustleSystem.day_of(w.tick)
	# a shift for clean money, once a day in the morning
	if w.tick < busy_until:
		return   # at work
	if day != shift_day and h >= 9.0 and h < 10.0:
		shift_day = day
		Wallet.earn_clean(w, SHIFT_PAY * CLEAN_SHIFT)
		income["shifts"] += SHIFT_PAY * CLEAN_SHIFT
		busy_until = w.tick + SimClock.hours(CLEAN_SHIFT)   # the hours pass at the counter
		return
	# broke: a mugging
	if me.cash < BROKE and w.tick - last_mug >= SimClock.hours(MUG_GAP_H):
		var v := _someone_near(200.0)
		if v != null:
			last_mug = w.tick
			_go(v.position + Vector2(1, 0))
			state.weapon = &"knife"
			state.aiming = true
			var c := me.cash
			if StreetCrime.mug(w, me, state, v).get("ok", false):
				counts["muggings"] += 1
				income["mugging"] += me.cash - c
			state.aiming = false
	# evenings: a shop
	if h >= 21.0 and day != robbed_day and state.case_evidence < 25.0:
		robbed_day = day
		var s := _shop_near(400.0)
		if s != null:
			_go(s.position)
			var c := me.cash
			if CrimeSystem.rob_building(w, s.id).get("ok", false):
				counts["robberies"] += 1
				income["robbery"] += me.cash - c
	_grow()
	_sell_weed()
	_business()

func _grow() -> void:
	var home: BuildingData = w.entities[me.home_building_id].get_component(ComponentNames.BUILDING)
	if int(state.grow.get("tents", 0)) == 0:
		if me.cash >= GROW_AT:
			var cost := 0
			for id in GROW_KIT:
				cost += int(ItemCatalog.item(id)["price"]) * int(GROW_KIT[id])
				state.inventory[id] = int(state.inventory.get(id, 0)) + int(GROW_KIT[id])
			Wallet.spend(w, cost)
			GrowSystem.install(w, state)
			GrowSystem.plant(w, state)
			_mark("grow set up")
		return
	if not StaffSystem.grower(state).is_empty():
		if int(state.grow.get("stash", {}).get("units", 0)) >= 6:
			GrowSystem.pick_up(w, state)
		return
	GrowSystem.water(w, state)
	if (state.grow.get("plants", []) as Array).any(func(pl: Dictionary) -> bool: return GrowSystem.ripe(w, pl)):
		if GrowSystem.harvest(w, state).get("ok", false):
			counts["grow_harvests"] += 1
	GrowSystem.bag(w, state)
	if (state.grow.get("plants", []) as Array).is_empty():
		state.inventory[&"seeds_kush"] = int(state.inventory.get(&"seeds_kush", 0)) + 4
		Wallet.spend(w, 4 * int(ItemCatalog.item(&"seeds_kush")["price"]))
		GrowSystem.plant(w, state)
	if me.cash >= GROWER_AT:
		var cands := StaffSystem.candidates(w, state, home.position)
		if not cands.is_empty() and StaffSystem.hire(w, state, cands[0], &"grow", "grower").get("ok", false):
			state.grow["stock"] = {&"seeds_kush": 12, &"plant_food": 12}
			Wallet.spend(w, 12 * int(ItemCatalog.item(&"seeds_kush")["price"]) + 12 * 8)
			_mark("grower hired")

func _sell_weed() -> void:
	for i in SELL_TRIES:
		if int(state.inventory.get(&"weed", 0)) <= 0:
			return
		var b := _someone_near(300.0)
		if b == null:
			return
		_go(b.position + Vector2(1, 0))
		var c := me.cash
		if StreetDeal.sell(w, me, state, b, &"weed").get("ok", false):
			counts["weed_sold"] += 1
			income["weed"] += me.cash - c

func _business() -> void:
	if shop == null:
		var cheapest: BuildingData = null
		for b in BusinessSystem.all_buildings(w):
			if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.daily_revenue > 0 and not BusinessSystem.owned_by_player(b) and (cheapest == null or BusinessSystem.price(b) < BusinessSystem.price(cheapest)):
				cheapest = b
		if cheapest != null and Wallet.clean(w) >= BusinessSystem.price(cheapest):
			_go(cheapest.position)
			if BusinessSystem.buy(w, cheapest.id).get("ok", false):
				shop = cheapest
				_mark("first business")
		return
	if not state.fronts.has(shop.id) and Wallet.clean(w) >= WASH_AT:
		if FrontSystem.convert(w, state, shop, "car_wash").get("ok", false):
			_mark("car wash")


func _someone_near(r: float) -> NPCData:
	var best: NPCData = null
	for id in w.spatial_index.query_nearby(me.position):
		var e: Entity = w.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_fixer or n.is_down or n.indoors) and n.gang_id == &"" and n.cash >= 0 and n.position.distance_to(me.position) <= r:
			if best == null or w.runtime_rng.randf() < 0.3:
				best = n
	return best

func _shop_near(r: float) -> BuildingData:
	for b in BusinessSystem.all_buildings(w):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.cash_on_hand > 0 and not BusinessSystem.owned_by_player(b) and b.position.distance_to(me.position) <= r:
			return b
	return null

func _go(p: Vector2) -> void:
	me.position = p
	w.reindex_position(me.id)

func _mark(what: String) -> void:
	if marks.has(what):
		return
	var t := float(w.tick) / SimClock.day_ticks
	marks[what] = "%d.%02d" % [int(t), int(fmod(t, 1.0) * 24.0)]
