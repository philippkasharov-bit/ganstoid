## E3: crime takes real money. A house's drawers hold that household's own
## cash (not a rolled number) and it does not come back by itself; drawers
## restock only if the household can pay for the goods. A shop's register is
## its real till: the float plus the day's takings. A mugging empties the
## wallet, which refills on payday. What the player takes the city loses.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 4242)
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var st: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	# A house with money at home.
	var house: BuildingData = null
	for b in BusinessSystem.all_buildings(world):
		if b.building_type == GanstoidEnums.BuildingType.RESIDENCE and b.cash_on_hand > 20 and b.id != me.home_building_id:
			house = b
			break
	me.position = house.position
	st.inside_id = house.id
	var city_before := EconomyFlow.total_money(world) + me.cash
	var had := house.cash_on_hand
	var cash_src: Array = Vicinity.near(world, me, st).filter(func(s: Dictionary) -> bool: return s["id"] == &"cash")
	ok = ok and cash_src.size() == 1 and cash_src[0]["n"] == had and cash_src[0]["cont"] == "bedroom"
	Vicinity.take(world, st, cash_src[0], 999)
	ok = ok and house.cash_on_hand == 0 and EconomyFlow.total_money(world) + me.cash == city_before   # moved, not made
	ok = ok and Vicinity.near(world, me, st).filter(func(s: Dictionary) -> bool: return s["id"] == &"cash").is_empty()
	# Emptied drawers do not refill for free: a broke household cannot restock.
	var drawers: Dictionary = house.containers["kitchen"]
	drawers["items"] = {}
	drawers["emptied_tick"] = world.tick - SimClock.day_ticks * 10
	house.bank = 0
	Containers.open(world, me, house)
	ok = ok and house.containers["kitchen"]["items"].is_empty()
	house.bank = 500
	Containers.open(world, me, house)
	var restock := LootTables.value(house.containers["kitchen"]["items"])
	ok = ok and (house.containers["kitchen"]["items"].is_empty() or house.bank == 500 - restock)
	# A shop's register is its till.
	var shop: BuildingData = null
	for b in BusinessSystem.all_buildings(world):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			shop = b
			break
	shop.cash_on_hand = 140
	shop.security = 0   # no camera: the whole till is in reach (E4)
	me.position = shop.position
	st.inside_id = shop.id
	var reg: Array = Vicinity.near(world, me, st).filter(func(s: Dictionary) -> bool: return s["id"] == &"cash")
	ok = ok and reg.size() == 1 and reg[0]["n"] == 140 and reg[0]["cont"] == "register"
	Vicinity.take(world, st, reg[0], 999)
	ok = ok and shop.cash_on_hand == 0 and shop.has_been_hit
	EconomyFlow.run_day(world)
	ok = ok and shop.cash_on_hand == shop.last_sales   # the float was robbed; the till now holds today's takings
	# A mugged wallet refills on payday.
	var worker: NPCData = null
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.wage > 0 and not e.has_component(ComponentNames.PLAYER_STATE):
			worker = n
			break
	worker.cash = 0
	EconomyFlow.run_day(world)
	ok = ok and worker.cash > 0
	print("house had $%d, register $140, restock $%d, worker paid back to $%d" % [had, restock, worker.cash])
	print("ECONOMY_CRIME_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
