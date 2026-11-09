## Batch 25: buying a grow house (clean money, safehouses only), daily
## growth with supply cost and storage cap, no growth when broke,
## collecting the harvest, and a raid seizing what's stored.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)

	var house_id := _a_safehouse(world)
	assert(house_id != &"", "worldgen has a safehouse")
	var house: BuildingData = world.entities[house_id].get_component(ComponentNames.BUILDING)
	pnpc.position = house.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

	# Buying: clean money only.
	pnpc.cash = ProductionSystem.GROW_HOUSE_PRICE
	state.dirty_cash = ProductionSystem.GROW_HOUSE_PRICE
	assert(ProductionSystem.buy(world, house_id)["reason"] == "need_clean_cash", "dirty can't buy it")
	state.dirty_cash = 0
	assert(ProductionSystem.buy(world, house_id)["ok"] and ProductionSystem.is_grow_house(house), "bought")
	assert(pnpc.cash == 0 and ProductionSystem.count_grow_houses(world) == 1, "paid, counted")
	assert(BusinessSystem.count_owned(world) == 0, "a grow house isn't counted as a shop")

	# Broke: no growth.
	assert(ProductionSystem.grow_all(world) == 0 and house.stored_product == 0, "can't pay supplies, nothing grows")

	# Paying: grows, costs supplies (dirty first).
	pnpc.cash = 1000
	state.dirty_cash = 1000
	assert(ProductionSystem.grow_all(world) == ProductionSystem.GROW_YIELD, "one day's yield")
	assert(pnpc.cash == 1000 - ProductionSystem.GROW_DAILY_COST and state.dirty_cash == 1000 - ProductionSystem.GROW_DAILY_COST, "supplies paid from dirty money")

	# Storage cap.
	for i in 20:
		ProductionSystem.grow_all(world)
	assert(house.stored_product == ProductionSystem.STORAGE_CAP, "stops at the cap")

	# Collect through the real Enter path order: own grow house wins.
	var weed_before: int = state.inventory.get(&"weed", 0)
	var r := ProductionSystem.collect(world, house_id)
	assert(r["ok"] and r["quantity"] == ProductionSystem.STORAGE_CAP, "harvest collected")
	assert(state.inventory[&"weed"] == weed_before + ProductionSystem.STORAGE_CAP and house.stored_product == 0, "into your stash")
	assert(ProductionSystem.collect(world, house_id)["reason"] == "nothing_grown", "empty house")

	# Raid seizes stored product.
	house.stored_product = 12
	assert(ProductionSystem.seize_stored(world, house) == 12 and house.stored_product == 0, "raid takes the stash")

	# Daily system actually fires in-world.
	house.stored_product = 0
	for i in SimClock.day_ticks + 20:
		world.step(1.0 / 60.0)
	assert(house.stored_product > 0, "a game day later it grew on its own")

	print("PHASE4_PRODUCTION_VERIFY: PASS")
	quit()

func _a_safehouse(world: World) -> StringName:
	for id in world.entities:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b != null and b.building_type == GanstoidEnums.BuildingType.SAFEHOUSE and CrimeSystem.find_territory_gang(world, id) == null:
			return id
	return &""
