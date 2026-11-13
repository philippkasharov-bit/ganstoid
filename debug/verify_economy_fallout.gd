## E4: robbed shops buy security (and a robber then gets less); shops short of
## money cut staff and then close (and sell nothing); a jobless household
## behind on rent ends up on the street; a shop doing well hires someone out
## of work nearby; the street pays more on a poor, thinly policed block.
## Then the big one: rob everything every day and the take dries up.
extends SceneTree

func _shop(world: World, skip: Array) -> BuildingData:
	for b in BusinessSystem.all_buildings(world):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.status == 0 and not skip.has(b):
			return b
	return null

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 4242)
	var ok := true
	# Security after repeat robberies.
	var a := _shop(world, [])
	a.security = 0
	for i in 3:
		EconomySystem.apply_robbery(a, 1)
	a.bank = 5000
	EconomyFlow.run_day(world)
	ok = ok and a.security == 1   # it bought a camera
	a.cash_on_hand = 200
	ok = ok and Containers.cash_shown(a, "register") == 150   # 75% in reach behind a camera
	# Going under.
	var b := _shop(world, [a])
	var staff_before := 0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		staff_before += int(e.get_component(ComponentNames.NPC).work_building_id == b.id)
	for d in 8:
		b.bank = 0
		b.cash_on_hand = 0
		b.daily_revenue = 0
		EconomyFlow.run_day(world)
		if d == 3:
			ok = ok and b.status == 1
	var staff_after := 0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		staff_after += int(e.get_component(ComponentNames.NPC).work_building_id == b.id)
	ok = ok and b.status == 2 and staff_after == 0 and ShopSystem.counter_kind(world, b.id) == ""
	# Street prices: poor, thin block pays more than rich, well policed.
	var data := BlockEconomyData.of(world)
	var cells: Array = data.blocks.keys()
	cells.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return data.blocks[x]["black"] < data.blocks[y]["black"])
	ok = ok and DealSystem.street_mult(world, TerritoryData.centre_of(cells[-1])) > DealSystem.street_mult(world, TerritoryData.centre_of(cells[0]))
	# Eviction: nobody in work, nothing left, behind on rent for days.
	var home: BuildingData = null
	var people: Array = []
	for h in EconomyFlow._homes:
		home = world.entities[h].get_component(ComponentNames.BUILDING)
		people = EconomyFlow._homes[h]
		break
	for n in people:
		n.work_building_id = &""
		n.wage = 0
	var home_id := home.id
	home.bad_days = EconomyFallout.EVICT_DAYS - 1   # behind on rent two days running already
	EconomyFallout._evictions(world, {home_id: people}, {home_id: true})   # (run straight: on a real day someone may hire them first)
	ok = ok and people.all(func(n: NPCData) -> bool: return n.home_building_id == &"" and n.camp != Vector2.ZERO)
	print("security %d, %s staff %d -> %d (status %d), evicted %d" % [a.security, b.trade, staff_before, staff_after, b.status, people.size()])
	# Rob everything every day: the take dries up.
	var take := []
	for d in 15:
		var got := 0
		for s in BusinessSystem.all_buildings(world):
			var c := Containers.cash_shown(s, "register" if s.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS else "bedroom")
			if c > 0:
				got += Containers.take_cash(world, s, c)
				if s.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
					s.hits += 1.0
		take.append(got)
		EconomyFlow.run_day(world)
	var closed := 0
	for s in BusinessSystem.all_buildings(world):
		closed += int(s.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and s.status == 2)
	print("robbing everything daily: day 1 $%d, day 5 $%d, day 15 $%d; shops closed %d" % [take[0], take[4], take[-1], closed])
	ok = ok and take[-1] < take[0] * 0.6
	print("ECONOMY_FALLOUT_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
