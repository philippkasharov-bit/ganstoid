## Standalone verification harness for Phase 2 batch 8: GangSeeder's
## minimal gang entities, dealer gang-affiliation assignment, and
## DealSystem's relationship-based (gang/solo standing) price discounts
## stacking on top of batch 7's market-reputation discount. Dev tool, not
## shipped content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_gangs_and_relationships.gd
extends SceneTree

const DECAY_STEPS := 3000

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)

	# --- Part 1: gangs actually got seeded, with territory and (for
	# affiliated dealers) membership wired up both directions.
	var gangs := world.get_entities_with_component(ComponentNames.GANG)
	assert(gangs.size() == GangSeeder.GANG_COUNT, "GangSeeder should have seeded exactly GANG_COUNT gangs")
	var total_members := 0
	for entity in gangs.values():
		var gang: GangData = entity.get_component(ComponentNames.GANG)
		total_members += gang.member_npc_ids.size()
		for member_id in gang.member_npc_ids:
			var member_npc: NPCData = world.entities[member_id].get_component(ComponentNames.NPC)
			assert(member_npc.gang_id == gang.id, "a gang's member list and that member's own gang_id must agree")
	print("seeded %d gangs, %d total affiliated dealers" % [gangs.size(), total_members])

	var dealer_ids: Array[StringName] = []
	var solo_found := false
	var affiliated_found := false
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and npc.is_dealer:
			dealer_ids.append(id)
			if npc.gang_id == &"":
				solo_found = true
			else:
				affiliated_found = true
	assert(solo_found, "the round-robin dealer assignment should leave at least one dealer solo")
	assert(affiliated_found, "the round-robin dealer assignment should affiliate at least one dealer with a gang")
	print("dealer affiliations: solo found=%s, gang-affiliated found=%s" % [solo_found, affiliated_found])

	# --- Part 2: relationship multiplier formula, same three landmarks as
	# batch 7's market-reputation check.
	var neutral_buy: float = DealSystem._relationship_buy_multiplier(0.5)
	var neutral_sell: float = DealSystem._relationship_sell_multiplier(0.5)
	assert(is_equal_approx(neutral_buy, 1.0) and is_equal_approx(neutral_sell, 1.0), "relationship 0.5 (neutral) must price exactly at current_price, both directions")
	var trusted_buy: float = DealSystem._relationship_buy_multiplier(1.0)
	assert(is_equal_approx(trusted_buy, 1.0 - DealSystem.RELATIONSHIP_PRICE_SWING), "max standing should give the cheapest buy multiplier")
	print("relationship multiplier formula checks out at the neutral/max landmarks")

	# --- Part 3: integration. A gang-affiliated dealer and a solo dealer
	# each build their own standing independently of each other and of
	# market reputation -- buying from one must not move the other's.
	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	player_npc.cash = 5000

	var gang_dealer_id := _find_dealer(world, dealer_ids, true)
	var solo_dealer_id := _find_dealer(world, dealer_ids, false)
	assert(gang_dealer_id != &"" and solo_dealer_id != &"", "need at least one of each kind of dealer to run this part")
	var gang_dealer_npc: NPCData = world.entities[gang_dealer_id].get_component(ComponentNames.NPC)
	var solo_dealer_npc: NPCData = world.entities[solo_dealer_id].get_component(ComponentNames.NPC)

	player_npc.position = gang_dealer_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	for i in 15:
		DealSystem.buy(world, gang_dealer_id, &"weed")
	var gang_standing: float = player_state.gang_standing.get(gang_dealer_npc.gang_id, 0.5)
	print("standing with %s after 15 buys: %.3f" % [gang_dealer_npc.gang_id, gang_standing])
	assert(gang_standing > 0.85, "repeated buying from a gang dealer should drive standing with their gang well above neutral")
	assert(player_state.solo_standing.get(solo_dealer_npc.id, 0.5) == 0.5, "buying from a gang dealer must not move an untouched solo's standing")

	player_npc.position = solo_dealer_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	DealSystem.buy(world, solo_dealer_id, &"weed")
	assert(player_state.solo_standing.get(solo_dealer_npc.id, 0.5) > 0.5, "buying from a solo dealer should raise standing with that specific NPC")
	assert(is_equal_approx(player_state.gang_standing.get(gang_dealer_npc.gang_id, 0.5), gang_standing), "buying from a solo dealer must not move the earlier gang standing")

	# A trusted gang dealer must actually be cheaper than a neutral one for
	# the same good at the same current_price -- the whole point of this
	# batch, checked end to end rather than just at the formula level.
	var weed: EconomyItemData = world.economy_items[&"weed"]
	var market_mult: float = DealSystem._buy_price_multiplier(weed.player_market_reputation)
	var trusted_cost := weed.current_price * market_mult * DealSystem._relationship_buy_multiplier(gang_standing)
	var neutral_cost := weed.current_price * market_mult * DealSystem._relationship_buy_multiplier(0.5)
	assert(trusted_cost < neutral_cost, "a trusted gang contact must price buys cheaper than an untouched one, all else equal")

	# --- Part 4: decay, same shape as batch 7's.
	for i in DECAY_STEPS:
		world.step(1.0 / 60.0)
	var decayed: float = player_state.gang_standing.get(gang_dealer_npc.gang_id, 0.5)
	print("gang standing after %d idle ticks: %.3f" % [DECAY_STEPS, decayed])
	assert(decayed < 0.6, "gang standing should decay most of the way back to neutral after a long dry spell")

	print("PHASE2_GANGS_AND_RELATIONSHIPS_VERIFY: PASS")
	quit()

func _find_dealer(world: World, dealer_ids: Array[StringName], want_affiliated: bool) -> StringName:
	for id in dealer_ids:
		var npc: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if (npc.gang_id != &"") == want_affiliated:
			return id
	return &""
