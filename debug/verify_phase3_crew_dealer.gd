## Batch 18: consignment, corner sales with a customer around, no sales
## without one, corner heat without player heat, and collecting.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)
	world.runtime_rng.seed = 2024
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)
	var civs := _civilians(world)
	var crew: NPCData = civs[0]
	crew.is_crew = true
	crew.cash = 0
	state.crew_ids.append(crew.id)

	# Nothing to hand over -> refused.
	assert(CrewDealerSystem.toggle(world, crew.id)["reason"] == "nothing_to_sell", "need stash to consign")

	# Post them right at a building so a recognized sale has a corner to heat.
	var spot: Vector2 = world.get_entities_with_component(ComponentNames.BUILDING).values()[0].get_component(ComponentNames.BUILDING).position
	crew.position = spot
	world.reindex_position(crew.id)

	# Consign 5 of 8.
	state.inventory[&"weed"] = 8
	assert(CrewDealerSystem.toggle(world, crew.id)["effect"] == "dealer_posted", "posted")
	assert(crew.crew_stash == 5 and state.inventory[&"weed"] == 3, "hands over CONSIGNMENT units")
	assert(CrewSystem.toggle_post(world, crew.id)["reason"] == "crew_busy", "can't flip a dealer to lookout mid-consignment")

	# No customers around -> no sales. (Walk the player off; crew holds post.)
	pnpc.position = crew.post_position + Vector2(500, 0)
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	for c in civs:
		if c != crew:
			c.position = Vector2(-50000, -50000)
			world.reindex_position(c.id)
	assert(not CrewDealerSystem.has_customer(world, crew.post_position), "nobody around")

	# A customer who never leaves (and recognizes on sight) -> sales happen,
	# the corner heats up, but the player's law tier never moves.
	var customer: NPCData = civs[1]
	customer.position = crew.post_position + Vector2(20, 0)
	world.reindex_position(customer.id)
	customer.is_busy = true  # pin them in place
	var heat_before := _max_heat(world)
	var heat_peak := heat_before
	for i in 6000:
		customer.recognition_chance = 1.0
		world.step(1.0 / 60.0)
		heat_peak = maxf(heat_peak, _max_heat(world))
	print("stash left=%d earnings=%d law=%d" % [crew.crew_stash, crew.crew_earnings, state.law_tier])
	assert(crew.crew_stash < 5, "corner sales happened")
	assert(crew.crew_earnings > 0, "made money")
	assert(state.law_tier == GanstoidEnums.LawTier.CLEAN, "player wasn't there -- no player heat")
	assert(heat_peak > heat_before, "but the corner got hot")

	# Collect.
	var cash_before := pnpc.cash
	var earned := crew.crew_earnings
	var left := crew.crew_stash
	var r := CrewDealerSystem.toggle(world, crew.id)
	var cut := int(floor(earned * CrewLoyaltySystem.CREW_CUT_FRACTION))
	assert(r["effect"] == "dealer_collected" and r["payout"] == earned - cut, "payout = sales minus cut")
	assert(pnpc.cash == cash_before + earned - cut and crew.cash == cut, "cash moved correctly")
	assert(state.inventory[&"weed"] == 3 + left and crew.crew_stash == 0, "unsold stash returned")
	assert(crew.crew_role == GanstoidEnums.CrewRole.UNASSIGNED, "back to following")

	print("PHASE3_CREW_DEALER_VERIFY: PASS")
	quit()

func _max_heat(world: World) -> float:
	var m := 0.0
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		m = maxf(m, e.get_component(ComponentNames.BUILDING).crime_heat)
	return m

func _civilians(world: World) -> Array:
	var out := []
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != null and not n.is_cop and not n.is_dealer and not e.has_component(ComponentNames.PLAYER_STATE):
			out.append(n)
	return out
