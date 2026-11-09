## Batch 23: buying a business (price, refusals, gang turf, ownership flag),
## the daily till payout, and owned shops being skipped by robbery-finding
## and by your own muscle.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)

	var shop_id := _first(world, GanstoidEnums.BuildingType.LEGIT_BUSINESS, false)
	var shop: BuildingData = world.entities[shop_id].get_component(ComponentNames.BUILDING)
	var cost := BusinessSystem.price(shop)
	assert(cost == shop.daily_revenue * BusinessSystem.PRICE_DAYS, "price = 10 days of revenue")

	assert(BusinessSystem.buy(world, shop_id)["reason"] == "too_far", "must be there")
	pnpc.position = shop.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	pnpc.cash = cost - 1
	assert(BusinessSystem.buy(world, shop_id)["reason"] == "cant_afford_business", "must afford it")
	pnpc.cash = cost + 100
	var r := BusinessSystem.buy(world, shop_id)
	assert(r["ok"] and r["cost"] == cost and pnpc.cash == 100, "bought at price")
	assert(BusinessSystem.owned_by_player(shop) and BusinessSystem.count_owned(world) == 1, "it's yours")
	assert(BusinessSystem.buy(world, shop_id)["reason"] == "already_yours", "can't buy twice")

	# Residences aren't for sale.
	var home_id := _first(world, GanstoidEnums.BuildingType.RESIDENCE, false)
	var home: BuildingData = world.entities[home_id].get_component(ComponentNames.BUILDING)
	pnpc.position = home.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	assert(BusinessSystem.buy(world, home_id)["reason"] == "not_for_sale", "homes aren't businesses")

	# Daily payout: till goes to you, then refills via EconomySystem regen.
	shop.cash_on_hand = 77
	var before := pnpc.cash
	assert(BusinessSystem.collect_all(world) == 77 and pnpc.cash == before + 77 and shop.cash_on_hand == 0, "till paid out")
	for i in SimClock.day_ticks + 20:
		world.step(1.0 / 60.0)
	print("cash after a day: %d (was %d), daily_revenue=%d" % [pnpc.cash, before + 77, shop.daily_revenue])
	assert(pnpc.cash > before + 77, "a game day later the shop paid again")

	# Muscle never shakes down your own shop.
	shop.cash_on_hand = shop.daily_revenue
	shop.protection_paid_tick = -1000000
	var muscle: NPCData = world.entities[&"npc_0"].get_component(ComponentNames.NPC)
	muscle.position = shop.position
	world.reindex_position(muscle.id)
	muscle.crew_earnings = 0
	CrewMuscleSystem.shake_down(world, muscle)
	assert(shop.cash_on_hand == shop.daily_revenue, "your own shop pays your muscle nothing")

	print("PHASE4_BUSINESS_VERIFY: PASS")
	quit()

func _first(world: World, kind: GanstoidEnums.BuildingType, gang_turf: bool) -> StringName:
	for id in world.entities:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b != null and b.building_type == kind and (CrimeSystem.find_territory_gang(world, id) != null) == gang_turf and (kind != GanstoidEnums.BuildingType.LEGIT_BUSINESS or b.daily_revenue > 0):
			return id
	return &""
