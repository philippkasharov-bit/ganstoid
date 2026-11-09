## Batch 12: ripoff chance scales with standing; a ripoff costs the player
## (paid, no product / product taken, half pay) and never more.
extends SceneTree

func _initialize() -> void:
	assert(is_equal_approx(DealSystem.ripoff_chance(1.0), 0.0), "trusted = never shorted")
	assert(is_equal_approx(DealSystem.ripoff_chance(0.5), DealSystem.RIPOFF_MAX_CHANCE * 0.5), "neutral = half max")
	assert(is_equal_approx(DealSystem.ripoff_chance(0.0), DealSystem.RIPOFF_MAX_CHANCE), "burned bridge = max")

	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	world.runtime_rng.seed = 12345
	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	var dealer_id := _find_a_dealer(world)
	var dealer_npc: NPCData = world.entities[dealer_id].get_component(ComponentNames.NPC)
	player_npc.position = dealer_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

	# Hostile standing, pinned each trade so gains don't drift it: ~30% ripoffs.
	var ripoffs := 0
	var trades := 400
	for i in trades:
		_set_standing(player_state, dealer_npc, 0.0)
		player_npc.cash = 100000
		var before: int = player_state.inventory.get(&"weed", 0)
		var r := DealSystem.buy(world, dealer_id, &"weed")
		var after: int = player_state.inventory.get(&"weed", 0)
		if r["ripped_off"]:
			ripoffs += 1
			assert(after == before, "a shorted buy delivers nothing")
		else:
			assert(after == before + 1, "a clean buy delivers one unit")
	var rate := float(ripoffs) / trades
	print("hostile ripoff rate: %.3f" % rate)
	assert(rate > 0.2 and rate < 0.4, "hostile standing should get shorted ~30% of the time")

	# Sell ripoff pays exactly the payout fraction of the clean price.
	player_state.inventory[&"weed"] = 1000
	var clean_seen := false
	var short_seen := false
	for i in 200:
		_set_standing(player_state, dealer_npc, 0.0)
		var r := DealSystem.sell(world, dealer_id, &"weed")
		assert(r["ok"] and r["proceeds"] >= 1, "sell always pays something")
		if r["ripped_off"]:
			short_seen = true
		else:
			clean_seen = true
	assert(clean_seen and short_seen, "both outcomes should occur at hostile standing")

	# Trusted dealer: zero ripoffs over many trades.
	for i in 200:
		_set_standing(player_state, dealer_npc, 1.0)
		player_npc.cash = 100000
		assert(not DealSystem.buy(world, dealer_id, &"weed")["ripped_off"], "trusted dealer never shorts you")

	print("PHASE2_DEAL_RIPOFF_VERIFY: PASS")
	quit()

func _set_standing(player_state: PlayerStateData, dealer_npc: NPCData, value: float) -> void:
	if dealer_npc.gang_id != &"":
		player_state.gang_standing[dealer_npc.gang_id] = value
	else:
		player_state.solo_standing[dealer_npc.id] = value

func _find_a_dealer(world: World) -> StringName:
	for id in world.entities:
		var npc: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if npc != null and npc.is_dealer:
			return id
	return &""
