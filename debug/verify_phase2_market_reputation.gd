## Standalone verification harness for EconomyItemData.player_market_
## reputation's payoff (Phase 2 batch 7): DealSystem's buy/sell price
## multipliers, the reputation gain those actions apply, and
## EconomySystem's decay of it back toward neutral. Dev tool, not shipped
## content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_market_reputation.gd
extends SceneTree

const DECAY_STEPS := 3000

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)

	# --- Part 1: the price-multiplier formula itself, checked directly at
	# the three reputation landmarks that matter -- neutral must be a true
	# no-op (a brand-new good's market prices identically to before this
	# batch), and the two extremes must swing in opposite directions for
	# buying vs. selling.
	var neutral_buy: float = DealSystem._buy_price_multiplier(0.5)
	var neutral_sell: float = DealSystem._sell_price_multiplier(0.5)
	assert(is_equal_approx(neutral_buy, 1.0) and is_equal_approx(neutral_sell, 1.0), "reputation 0.5 (neutral) must price exactly at current_price, both directions")

	var trusted_buy: float = DealSystem._buy_price_multiplier(1.0)
	var trusted_sell: float = DealSystem._sell_price_multiplier(1.0)
	assert(is_equal_approx(trusted_buy, 1.0 - DealSystem.REPUTATION_PRICE_SWING), "max reputation should give the cheapest buy multiplier")
	assert(is_equal_approx(trusted_sell, 1.0 + DealSystem.REPUTATION_PRICE_SWING), "max reputation should give the best sell multiplier")

	var distrusted_buy: float = DealSystem._buy_price_multiplier(0.0)
	var distrusted_sell: float = DealSystem._sell_price_multiplier(0.0)
	assert(is_equal_approx(distrusted_buy, 1.0 + DealSystem.REPUTATION_PRICE_SWING), "zero reputation should give the priciest buy multiplier")
	assert(is_equal_approx(distrusted_sell, 1.0 - DealSystem.REPUTATION_PRICE_SWING), "zero reputation should give the worst sell multiplier")
	print("price multiplier formula checks out at reputation 0.0 / 0.5 / 1.0")

	# --- Part 2: integration -- a brand-new good's market (reputation still
	# at its 0.5 default) must charge exactly current_price on the very
	# first buy, then reputation must actually rise from repeated trades.
	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	player_npc.cash = 2000

	var dealer_id := _find_a_dealer(world)
	assert(dealer_id != &"", "PopulationSeeder should have seeded at least one dealer")
	var dealer_npc: NPCData = world.entities[dealer_id].get_component(ComponentNames.NPC)
	player_npc.position = dealer_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

	var weed: EconomyItemData = world.economy_items[&"weed"]
	assert(is_equal_approx(weed.player_market_reputation, 0.5), "a fresh game's goods should start at neutral reputation")
	var first_buy := DealSystem.buy(world, dealer_id, &"weed")
	assert(first_buy.get("ok", false), "first buy should succeed")
	assert(first_buy["cost"] == weed.current_price * DealSystem.TRADE_QUANTITY, "the very first trade (neutral reputation) must cost exactly current_price -- no surprise discount/markup before any history exists")

	for i in 19:
		DealSystem.buy(world, dealer_id, &"weed")
	print("reputation after 20 buys: %.3f" % weed.player_market_reputation)
	assert(weed.player_market_reputation > 0.9, "repeated buying should drive reputation well above neutral")

	# --- Part 3: decay. With no further trades, reputation should fade
	# back toward 0.5 over enough warm ticks -- same "a relationship lapses
	# if you stop maintaining it" shape as everything else this phase.
	for i in DECAY_STEPS:
		world.step(1.0 / 60.0)
	print("reputation after %d idle ticks: %.3f" % [DECAY_STEPS, weed.player_market_reputation])
	assert(weed.player_market_reputation < 0.6, "reputation should decay most of the way back to neutral after a long dry spell")

	print("PHASE2_MARKET_REPUTATION_VERIFY: PASS")
	quit()

func _find_a_dealer(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_dealer:
			return id
	return &""
