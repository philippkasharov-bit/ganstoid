## Batch 11: a deal takes HANDOFF_TICKS, roots both sides, and only then
## completes through the normal buy/sell path.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)

	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	player_npc.cash = 500
	# Park every cop far away so a random witness->arrest can't interrupt the
	# timing checks below (that path is tested separately at the end).
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)

	var dealer_id := _find_a_dealer(world)
	var dealer_npc: NPCData = world.entities[dealer_id].get_component(ComponentNames.NPC)
	_trust(player_state, dealer_npc)  # batch 12: standing 1.0 = zero ripoff chance, keeps inventory asserts exact
	player_npc.position = dealer_npc.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

	var refused := DealSystem.start_handoff(world, dealer_id, &"weed", "sell")
	assert(refused.get("reason", "") == "nothing_to_sell", "can't start a sell with nothing held")

	var started := DealSystem.start_handoff(world, dealer_id, &"weed", "buy")
	assert(started.get("ok", false), "handoff should start in range")
	assert(dealer_npc.is_busy, "dealer should be marked busy")
	assert(DealSystem.start_handoff(world, dealer_id, &"weed", "buy").get("reason", "") == "already_dealing", "no stacking deals")

	var dealer_pos := dealer_npc.position
	var player_pos := player_npc.position
	var cash_before := player_npc.cash
	for i in DealSystem.HANDOFF_TICKS - 1:
		world.step(1.0 / 60.0)
	assert(not player_state.pending_deal.is_empty(), "deal should still be in progress one tick before the end")
	assert(player_npc.cash == cash_before, "no money moves until the handoff completes")
	assert(dealer_npc.position == dealer_pos, "dealer should stay rooted")
	assert(player_npc.position == player_pos, "player should stay rooted")

	_trust(player_state, dealer_npc)  # standing decays toward neutral during the handoff; re-pin so no ripoff roll
	world.step(1.0 / 60.0)
	assert(player_state.pending_deal.is_empty(), "deal should be finished")
	assert(not dealer_npc.is_busy, "dealer should be released")
	assert(player_state.inventory.get(&"weed", 0) == 1, "buy should land after the handoff")
	assert(player_npc.cash < cash_before, "cash should drop after the handoff")

	# Arrest mid-handoff: deal cancelled, dealer released, nothing traded.
	DealSystem.start_handoff(world, dealer_id, &"weed", "buy")
	var held: int = player_state.inventory.get(&"weed", 0)
	DealSystem.cancel_handoff(world, player_state)
	assert(player_state.pending_deal.is_empty() and not dealer_npc.is_busy, "cancel should clear the deal and free the dealer")
	assert(player_state.inventory.get(&"weed", 0) == held, "a cancelled deal trades nothing")

	print("PHASE2_DEAL_HANDOFF_VERIFY: PASS")
	quit()

func _find_a_dealer(world: World) -> StringName:
	for id in world.entities:
		var npc: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if npc != null and npc.is_dealer:
			return id
	return &""

func _trust(player_state: PlayerStateData, dealer_npc: NPCData) -> void:
	if dealer_npc.gang_id != &"":
		player_state.gang_standing[dealer_npc.gang_id] = 1.0
	else:
		player_state.solo_standing[dealer_npc.id] = 1.0
