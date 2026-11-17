## QL3 validator: quality reads as street words per drug (and for staff and
## night spots); strains differ: Skunk #1 yields more and stinks more than
## Northern Lights, which ripens faster; each sells best where it fits;
## mixing strains loses the name; pills differ by powder; your asking price
## decides how many buyers bite (all at its worth, half at 1.5x) and what
## each pays on a crew corner; the phone sets and clears the price.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	w.tick = SimClock.hours(32.0)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	ok = _check(Grades.drug(&"weed", 4.6) == "Chronic" and Grades.drug(&"coke", 1.2) == "Baking soda" and Grades.drug(&"heroin", 5.0) == "China white", "quality in street words (Chronic, Baking soda, China white)") and ok
	ok = _check(Grades.staff(1.0) == "A pro" and Grades.venue(4) == "Hot spot", "workers and night spots in words too") and ok
	# strains
	state.grow = {"tents": 2, "lamp": 2, "fan": true, "filter": false, "plants": [], "drying": []}
	var skunk := {"strain": &"seeds_skunk", "at": w.tick, "watered": w.tick, "fed": 2, "care": 1.0}
	var nl := {"strain": &"seeds_nl", "at": w.tick, "watered": w.tick, "fed": 2, "care": 1.0}
	ok = _check(GrowSystem.yield_of(state, skunk) > GrowSystem.yield_of(state, nl), "Skunk #1 yields more (%d vs %d a plant)" % [GrowSystem.yield_of(state, skunk), GrowSystem.yield_of(state, nl)]) and ok
	w.tick += int(GrowSystem.GROW_DAYS * 0.85 * SimClock.day_ticks)
	ok = _check(GrowSystem.ripe(w, nl) and not GrowSystem.ripe(w, skunk), "Northern Lights ripens sooner") and ok
	var smell := []
	for sid in [&"seeds_skunk", &"seeds_nl"]:
		state.grow["plants"] = []
		for i in 8:
			state.grow["plants"].append({"strain": sid, "at": w.tick, "watered": w.tick, "fed": 0, "care": 1.0})
		state.case_evidence = 0.0
		for h in 300:
			w.tick += SimClock.hours(0.25)
			GrowSystem.water(w, state)
			GrowSystem.tend_hour(w, me, state, w.tick)
		smell.append(state.case_evidence)
	ok = _check(smell[0] > smell[1] * 1.5, "Skunk #1 stinks more (case %.0f vs %.0f)" % [smell[0], smell[1]]) and ok
	ok = _check(is_equal_approx(GrowSystem.STRAINS[&"seeds_kush"]["base"], 3.2) and GrowSystem.STRAINS.size() == 6, "six strains") and ok
	# where it sells
	state.inventory[&"weed"] = 0
	GrowSystem.add_product(state, 10, 4.0, "seeds_kush")
	ok = _check(Grades.fit(state, &"weed", 0.2, false) > 1.0 and Grades.fit(state, &"weed", 0.8, false) == 1.0, "OG Kush sells best on poor corners") and ok
	ok = _check(Grades.about(state, &"weed").contains("heavy body high"), "and says what it does: %s" % Grades.about(state, &"weed")) and ok
	GrowSystem.add_product(state, 10, 4.0, "seeds_haze")
	ok = _check(String(state.product["strain"]) == "" and Grades.fit(state, &"weed", 0.2, false) == 1.0, "mixed strains lose their name") and ok
	state.inventory[&"weed"] = 0
	GrowSystem.add_product(state, 10, 4.0, "seeds_haze")
	ok = _check(Grades.fit(state, &"weed", 0.5, true) > 1.0, "Purple Haze sells best in clubs") and ok
	# pills by powder
	state.lab = {"press": true}
	state.inventory[&"pill_powder"] = 2
	DrugLabSystem.press(w, state)
	ok = _check(String(state.products["pills_kind"]) == "pill_powder" and Grades.about(state, &"pills").contains("clubs"), "MDMA powder makes doves, for the clubs") and ok
	state.inventory[&"speed_powder"] = 2
	DrugLabSystem.press(w, state)
	ok = _check(String(state.products["pills_kind"]) == "", "mixed with speedy whites they lose their name") and ok
	# prices
	ok = _check(is_equal_approx(DrugLabSystem.accept(20, 20), 1.0) and is_equal_approx(DrugLabSystem.accept(30, 20), 0.5) and DrugLabSystem.accept(60, 20) <= 0.05, "all buyers at its worth, half at 1.5x, hardly any at 3x") and ok
	var lab := w.find_system(DrugLabSystem) as DrugLabSystem
	state.ui_lab = {"price": &"weed", "set": 33}
	lab.process_entities({PlayerFactory.PLAYER_ENTITY_ID: p}, 0.0, w.tick)
	ok = _check(int(state.prices[&"weed"]) == 33, "the phone sets your price") and ok
	state.ui_lab = {"price": &"weed", "set": 0}
	lab.process_entities({PlayerFactory.PLAYER_ENTITY_ID: p}, 0.0, w.tick)
	ok = _check(not state.prices.has(&"weed"), "and puts it back to the going rate") and ok
	# on a crew corner
	var fair := _corner(w, me, state, 0)
	var dear := _corner(w, me, state, 2)
	print("4000 tries: fair price %d sales ($%d each), double %d sales ($%d each)" % [fair[0], fair[1], dear[0], dear[1]])
	ok = _check(dear[0] < fair[0] * 0.5 and dear[1] > fair[1], "ask double and few buy, but each pays more") and ok
	if ok:
		print("QUALITY_VERIFY: PASS")
	quit(0 if ok else 1)

## Sales on a crew corner at worth x `times` (0: the going rate): [sales, $ each].
func _corner(w: World, me: NPCData, state: PlayerStateData, times: int) -> Array:
	var sys := w.find_system(CrewDealerSystem) as CrewDealerSystem
	var dealer: NPCData = null
	var buyer: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_down) and n.gang_id == &"":
			if dealer == null:
				dealer = n
			elif buyer == null:
				buyer = n
				break
	dealer.is_crew = true
	dealer.position = buyer.position + Vector2(3, 0)
	w.reindex_position(dealer.id)
	state.memories = {}
	var worth := DrugLabSystem.value_each(w, state, &"weed", dealer.position, false)
	if times > 0:
		state.prices[&"weed"] = roundi(worth * times)
	else:
		state.prices.erase(&"weed")
	var sales := 0
	var each := 0
	for i in 4000:
		dealer.crew_stash = 5
		var before := dealer.crew_earnings
		sys._try_sale(dealer)
		if dealer.crew_earnings > before:
			sales += 1
			each = dealer.crew_earnings - before
			state.memories = {}   # nobody becomes a regular in this test
	return [sales, each]

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("QUALITY_VERIFY: FAIL - " + what)
	return good
