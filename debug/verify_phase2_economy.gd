## Standalone verification harness for the Phase 2 economy core (pricing
## drift + cash-on-hand regen). Dev tool, not shipped content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_economy.gd
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)

	assert(world.economy_items.has(&"weed"), "GoodsCatalog should have seeded 'weed'")
	var weed: EconomyItemData = world.economy_items[&"weed"]
	print("weed before: price=%d demand=%.3f supply=%.3f" % [weed.current_price, weed.demand, weed.supply])
	assert(weed.current_price == weed.base_price, "price should start at base_price with neutral demand/supply")

	# Simulate heavy buying pressure on weed, then let the sim run and
	# confirm price actually rises, then confirm it decays back down once
	# the pressure stops -- proving both halves of the drift, not just one.
	EconomySystem.record_trade(weed, 0.9, 0.9)
	print("weed after trade: demand=%.3f supply=%.3f" % [weed.demand, weed.supply])

	for i in 50:  # 50 ticks = 5 warm ticks at WARM_TICK_INTERVAL=10
		world.step(1.0 / 60.0)
	print("weed after 50 ticks: price=%d demand=%.3f supply=%.3f" % [weed.current_price, weed.demand, weed.supply])
	assert(weed.current_price > weed.base_price, "heavy buy pressure should have pushed price above base")

	var price_after_trade := weed.current_price
	for i in 2000:  # let demand/supply decay most of the way back to 0.5
		world.step(1.0 / 60.0)
	print("weed after 2000 more ticks: price=%d demand=%.3f supply=%.3f" % [weed.current_price, weed.demand, weed.supply])
	assert(weed.current_price < price_after_trade, "price should decay back down as demand/supply return toward baseline")
	assert(absf(weed.demand - 0.5) < 0.05, "demand should have decayed back near baseline after 2000 ticks")

	# Cash-on-hand regen: drain a legit business to zero, confirm it claws
	# back toward daily_revenue on its own over time.
	var business_id := _find_legit_business(world)
	assert(business_id != &"", "city should have at least one LEGIT_BUSINESS")
	var business: BuildingData = world.entities[business_id].get_component(ComponentNames.BUILDING)
	EconomySystem.apply_robbery(business, business.cash_on_hand)
	print("business after robbery: cash_on_hand=%d daily_revenue=%d has_been_hit=%s" % [business.cash_on_hand, business.daily_revenue, business.has_been_hit])
	assert(business.cash_on_hand == 0, "robbery should have drained cash_on_hand to 0")
	assert(business.has_been_hit, "robbery should flag has_been_hit")

	for i in 500:
		world.step(1.0 / 60.0)
	print("business after 500 ticks: cash_on_hand=%d / daily_revenue=%d" % [business.cash_on_hand, business.daily_revenue])
	assert(business.cash_on_hand > 0, "cash_on_hand should have regenerated at least partially after 500 ticks")

	print("PHASE2_ECONOMY_VERIFY: PASS")
	quit()

func _find_legit_business(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building != null and building.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and building.daily_revenue > 0:
			return id
	return &""
