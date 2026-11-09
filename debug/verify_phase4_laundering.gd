## Batch 24: crime money comes in dirty, shop money clean; spending burns
## dirty first; businesses need clean money; arrest seizes half the dirty;
## shops launder up to their daily revenue at a 20% fee.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	pnpc.cash = 0
	state.dirty_cash = 0

	# Earning.
	Wallet.earn_dirty(world, 300)
	Wallet.earn_clean(world, 100)
	assert(pnpc.cash == 400 and state.dirty_cash == 300 and Wallet.clean(world) == 100, "dirty + clean tracked")

	# Spending burns dirty first.
	Wallet.spend(world, 50)
	assert(state.dirty_cash == 250 and Wallet.clean(world) == 100, "dirty spent first")

	# Real crime income is dirty: rob a shop.
	var shop_id := _a_shop(world)
	var shop: BuildingData = world.entities[shop_id].get_component(ComponentNames.BUILDING)
	pnpc.position = shop.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	shop.cash_on_hand = 200
	var dirty_before := state.dirty_cash
	var r := CrimeSystem.rob_building(world, shop_id)
	assert(r["ok"] and state.dirty_cash == dirty_before + r["taken"], "robbery money is dirty")

	# Buying a business needs clean money.
	shop.cash_on_hand = shop.daily_revenue
	var cost := BusinessSystem.price(shop)
	pnpc.cash = cost + 500
	state.dirty_cash = cost  # plenty of total, not enough clean
	assert(BusinessSystem.buy(world, shop_id)["reason"] == "need_clean_cash", "dirty money can't buy a business")
	state.dirty_cash = 500  # now exactly `cost` is clean
	assert(BusinessSystem.buy(world, shop_id)["ok"], "clean money can")
	assert(state.dirty_cash == 500 and pnpc.cash == 500, "only clean money was spent")

	# Laundering: capacity = owned daily revenue, 20% fee.
	var cap := BusinessSystem.laundering_capacity(world)
	assert(cap == shop.daily_revenue, "capacity = your shops' daily revenue")
	var washed: Dictionary = Wallet.launder(world, cap, BusinessSystem.LAUNDER_FEE)
	var expected_wash := mini(500, cap)
	assert(washed["washed"] == expected_wash and washed["fee"] == ceili(expected_wash * BusinessSystem.LAUNDER_FEE), "washed up to capacity, fee charged")
	assert(state.dirty_cash == 500 - expected_wash and pnpc.cash == 500 - washed["fee"], "dirty became clean minus fee")

	# Arrest seizes half the dirty money, none of the clean.
	state.dirty_cash = 200
	pnpc.cash = 300
	var seized := Wallet.seize_dirty(world, CopAISystem.ARREST_SEIZE_FRACTION)
	assert(seized == 100 and state.dirty_cash == 100 and pnpc.cash == 200, "half the dirty money seized, clean untouched")

	print("PHASE4_LAUNDERING_VERIFY: PASS")
	quit()

func _a_shop(world: World) -> StringName:
	for id in world.entities:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b != null and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.daily_revenue > 0 and CrimeSystem.find_territory_gang(world, id) == null:
			return id
	return &""
