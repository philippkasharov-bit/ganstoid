## Standalone verification harness for the drug-deal buy/sell action
## (DealSystem) layered on top of the Phase 2 economy core. Dev tool, not
## shipped content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_deals.gd
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)

	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	player_npc.cash = 500  # give the player enough to actually afford a few buys

	var dealer_id := _find_a_dealer(world)
	assert(dealer_id != &"", "PopulationSeeder should have seeded at least one dealer")
	print("dealer found: ", dealer_id)
	var dealer_npc: NPCData = world.entities[dealer_id].get_component(ComponentNames.NPC)
	_trust(player_state, dealer_npc)  # batch 12: standing 1.0 = zero ripoff chance, keeps inventory asserts exact

	# Too-far check: buying should fail cleanly before we're in range.
	var far_result := DealSystem.buy(world, dealer_id, &"weed")
	print("buy from far away: ", far_result)
	assert(far_result.get("reason", "") == "too_far", "buy should refuse when not near the dealer")

	player_npc.position = dealer_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

	var weed: EconomyItemData = world.economy_items[&"weed"]
	var cash_before := player_npc.cash
	var demand_before := weed.demand
	var buy_result := DealSystem.buy(world, dealer_id, &"weed")
	print("buy: ", buy_result, " cash=%d inventory=%s demand=%.3f" % [player_npc.cash, player_state.inventory, weed.demand])
	assert(buy_result.get("ok", false), "buy should succeed once in range with enough cash")
	assert(player_npc.cash == cash_before - buy_result["cost"], "cash should drop by exactly the quoted cost")
	assert(player_state.inventory.get(&"weed", 0) == 1, "inventory should hold 1 weed after one buy")
	assert(weed.demand > demand_before, "buying should nudge demand up")

	var buy_result_2 := DealSystem.buy(world, dealer_id, &"weed")
	assert(buy_result_2.get("ok", false), "second buy should also succeed")
	assert(player_state.inventory.get(&"weed", 0) == 2, "inventory should hold 2 weed after two buys")

	var cash_before_sell := player_npc.cash
	var supply_before := weed.supply
	var sell_result := DealSystem.sell(world, dealer_id, &"weed")
	print("sell: ", sell_result, " cash=%d inventory=%s supply=%.3f" % [player_npc.cash, player_state.inventory, weed.supply])
	assert(sell_result.get("ok", false), "sell should succeed with 1+ unit held")
	assert(player_state.inventory.get(&"weed", 0) == 1, "inventory should drop to 1 weed after selling one")
	assert(player_npc.cash == cash_before_sell + sell_result["proceeds"], "cash should rise by exactly the quoted proceeds")
	assert(weed.supply > supply_before, "selling should nudge supply up")

	# Drain inventory to 0 and confirm a third sell is refused, not silently
	# allowed to go negative.
	DealSystem.sell(world, dealer_id, &"weed")
	var overdraw := DealSystem.sell(world, dealer_id, &"weed")
	print("sell with nothing held: ", overdraw)
	assert(overdraw.get("reason", "") == "nothing_to_sell", "selling with empty inventory should be refused")

	print("PHASE2_DEALS_VERIFY: PASS")
	quit()

func _find_a_dealer(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_dealer:
			return id
	return &""

func _trust(player_state: PlayerStateData, dealer_npc: NPCData) -> void:
	if dealer_npc.gang_id != &"":
		player_state.gang_standing[dealer_npc.gang_id] = 1.0
	else:
		player_state.solo_standing[dealer_npc.id] = 1.0
