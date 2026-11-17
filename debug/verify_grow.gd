## BZ1 validator: gear goes up at home (tents capped by the crib); seeds go
## in; plants get thirsty, wilt and die if left; they ripen in two days and
## hang to dry; bagged weed carries stars (a shop light caps them, an HPS
## lamp, fan and food raise them) and your stamp; stars and brand set the
## price (street weed unchanged); cutting stretches it a star down; a good
## crew-corner sale makes a regular; good sales build the brand until the
## street asks for it by name; the smell tips off neighbours (less with a
## filter); you can rename your stamp.
extends SceneTree

var w: World
var state: PlayerStateData
var me: NPCData

func _initialize() -> void:
	w = World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	w.tick = SimClock.hours(32.0)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	me = p.get_component(ComponentNames.NPC)
	state = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	# gear
	for id in [&"grow_tent", &"grow_tent", &"shop_light", &"grow_fan", &"plant_food"]:
		state.inventory[id] = int(state.inventory.get(id, 0)) + 1
	state.inventory[&"plant_food"] = 8
	var r := GrowSystem.install(w, state)
	ok = _check(r["ok"] and int(state.grow["tents"]) == 1 and int(state.inventory.get(&"grow_tent", 0)) == 1 and int(state.grow["lamp"]) == 1 and state.grow["fan"], "gear goes up; a Mattress crib fits one tent (the other stays in the bag)") and ok
	# planting
	state.inventory[&"seeds_kush"] = 4
	state.inventory[&"seeds_mids"] = 1
	r = GrowSystem.plant(w, state)
	ok = _check(r["ok"] and state.grow["plants"].size() == 4 and int(state.inventory.get(&"seeds_mids", 0)) == 1, "four plants in one tent, best seeds first") and ok
	var plants: Array = state.grow["plants"]
	# thirst
	_hours(13)
	ok = _check(GrowSystem.thirsty(w, plants[0]) and GrowSystem.need_line(w, state).contains("need water"), "after 12 hours they're thirsty and the pager says so") and ok
	ok = _check(float(plants[0]["care"]) < 1.0, "a thirsty plant wilts (care %.2f)" % float(plants[0]["care"])) and ok
	GrowSystem.water(w, state)
	GrowSystem.feed(w, state)
	GrowSystem.feed(w, state)
	ok = _check(not GrowSystem.thirsty(w, plants[0]) and int(plants[0]["fed"]) == 2, "watered and fed twice") and ok
	# keep them watered until ripe
	for i in 4:
		_hours(10)
		GrowSystem.water(w, state)
	_hours(int(GrowSystem.GROW_DAYS * 24) - 53)
	ok = _check(GrowSystem.ripe(w, plants[0]) and GrowSystem.need_line(w, state).contains("ready"), "ripe after two days") and ok
	var q := GrowSystem.quality(state, plants[0])
	ok = _check(q <= GrowSystem.SHOP_LIGHT_CAP, "a shop light caps the stars (%.1f)" % q) and ok
	r = GrowSystem.harvest(w, state)
	ok = _check(r["ok"] and state.grow["plants"].is_empty() and state.grow["drying"].size() == 4, "harvested: %d bags hang to dry" % int(r["amount"])) and ok
	ok = _check(not GrowSystem.bag(w, state)["ok"], "not dry yet") and ok
	_hours(13)
	var weed_before: int = state.inventory.get(&"weed", 0)
	r = GrowSystem.bag(w, state)
	ok = _check(r["ok"] and int(state.inventory[&"weed"]) == weed_before + int(r["amount"]) and state.brand != "", "bagged %d, stamped '%s' %s" % [int(r["amount"]), state.brand, GrowSystem.stars_text(GrowSystem.stars_carried(state))]) and ok
	# a better setup grows better weed
	state.grow["lamp"] = 2
	var good := {"strain": &"seeds_haze", "at": 0, "watered": w.tick, "fed": 2, "care": 1.0}
	ok = _check(GrowSystem.quality(state, good) >= 4.5, "HPS lamp, fan, food and haze: %s" % GrowSystem.stars_text(GrowSystem.quality(state, good))) and ok
	# price
	var street := PlayerStateData.new()
	ok = _check(is_equal_approx(GrowSystem.price_mult(street), 1.0), "street weed sells as it always did") and ok
	state.product = {"q": 4.6, "strain": "Purple Haze"}
	ok = _check(GrowSystem.price_mult(state) > 1.6, "top weed fetches more (x%.2f)" % GrowSystem.price_mult(state)) and ok
	# cutting
	state.inventory[&"weed"] = 10
	r = GrowSystem.cut(w, state)
	ok = _check(int(state.inventory[&"weed"]) == 15 and is_equal_approx(GrowSystem.stars_carried(state), 3.6), "cutting: 10 -> 15 bags, a star off") and ok
	# brand
	state.product["q"] = 4.5
	state.brand_rep = 0.0
	var inbox := state.inbox.size()
	for i in 16:
		GrowSystem.sold(w, state)
	ok = _check(state.brand_rep >= 0.3 and state.inbox.size() > inbox and String(state.inbox[-1]["text"]).contains(state.brand), "good sales build the brand; the street asks for it by name") and ok
	# a regular from a crew corner
	ok = _check(_regular(), "a good sale on your corner makes a regular, who pays more next time") and ok
	# smell
	state.grow["plants"] = []
	for i in 8:
		state.grow["plants"].append({"strain": &"seeds_mids", "at": w.tick, "watered": w.tick, "fed": 0, "care": 1.0})
	state.grow["filter"] = false
	state.case_evidence = 0.0
	for i in 60:
		w.tick += SimClock.hours(0.2)
		GrowSystem.water(w, state)
		GrowSystem.tend_hour(w, me, state, w.tick)
	var open_case := state.case_evidence
	state.grow["filter"] = true
	state.case_evidence = 0.0
	for i in 60:
		w.tick += SimClock.hours(0.2)
		GrowSystem.water(w, state)
		GrowSystem.tend_hour(w, me, state, w.tick)
	ok = _check(open_case > 0.0 and state.case_evidence < open_case, "the smell reaches the neighbours (case %.0f), a filter cuts it (%.0f)" % [open_case, state.case_evidence]) and ok
	# rename
	var grow := w.find_system(GrowSystem) as GrowSystem
	state.ui_grow = {"brand": "  Boyle Heights Kush  "}
	var t := w.tick + posmod(GrowSystem.PHASE - w.tick, GrowSystem.EVERY)
	grow.process_entities({PlayerFactory.PLAYER_ENTITY_ID: w.entities[PlayerFactory.PLAYER_ENTITY_ID]}, 0.0, t)
	ok = _check(state.brand == "Boyle Heights Kush", "rename your stamp") and ok
	if ok:
		print("GROW_VERIFY: PASS")
	quit(0 if ok else 1)

func _hours(h: int) -> void:
	for i in h:
		w.tick += SimClock.hours(1.0)
		GrowSystem.tend_hour(w, me, state, w.tick)

## A crew dealer on a corner with a buyer close by; returns true once a 4-star
## sale has made that buyer a regular and the next sale paid them more.
func _regular() -> bool:
	var dealer: NPCData = null
	var buyer: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_fixer or n.is_down) and n.gang_id == &"":
			if dealer == null:
				dealer = n
			elif n.position.distance_to(dealer.position) > 200.0:
				buyer = n
				break
	dealer.is_crew = true
	dealer.position = me.position + Vector2(40, 0)
	buyer.position = dealer.position + Vector2(3, 0)
	w.reindex_position(dealer.id)
	w.reindex_position(buyer.id)
	var sys := w.find_system(CrewDealerSystem) as CrewDealerSystem
	var who := sys.customer(w, dealer.position)
	state.product["q"] = 4.5
	var first := 0
	for i in 4000:
		if sys.customer(w, dealer.position) != who:
			return false
		dealer.crew_stash = 5
		state.brand_rep = 0.0
		var was_regular := MemorySystem.feel_of(state, who) >= CrewDealerSystem.REGULAR_AT
		var before := dealer.crew_earnings
		sys._try_sale(dealer)
		var got := dealer.crew_earnings - before
		if got > 0 and first == 0:
			first = got
		elif got > 0 and was_regular:
			print("  first sale $%d, as a regular $%d" % [first, got])
			return got > first
	return false

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("GROW_VERIFY: FAIL - " + what)
	return good
