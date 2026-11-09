## Batch 19: protection money -- right amount from the shop's own register,
## once per day per shop, never from gang turf, never the player's heat;
## collecting pays out minus the cut; busy crew can't be double-booked.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)
	var crew := _first_civilian(world)
	crew.is_crew = true
	crew.cash = 0
	state.crew_ids.append(crew.id)

	# Find a legit shop, stand the muscle on it.
	var shop_id := _first_shop(world)
	var shop: BuildingData = world.entities[shop_id].get_component(ComponentNames.BUILDING)
	crew.position = shop.position
	world.reindex_position(crew.id)
	assert(CrewMuscleSystem.toggle(world, crew.id)["effect"] == "muscle_posted", "posted")
	assert(CrewSystem.toggle_post(world, crew.id)["reason"] == "crew_busy", "muscle can't be made a lookout mid-job")
	assert(CrewDealerSystem.toggle(world, crew.id)["reason"] == "crew_busy", "or a dealer")

	# One shakedown: exact cut from this shop's register.
	world.tick = 5000
	shop.cash_on_hand = shop.daily_revenue
	var expected := ceili(shop.daily_revenue * CrewMuscleSystem.PROTECTION_FRACTION)
	var before := crew.crew_earnings
	CrewMuscleSystem.shake_down(world, crew)
	assert(shop.cash_on_hand == shop.daily_revenue - expected, "takes PROTECTION_FRACTION of daily revenue")
	assert(crew.crew_earnings - before >= expected and shop.protection_paid_tick == 5000, "muscle holds it; shop marked paid")

	# Same day: shop won't pay twice.
	var held := crew.crew_earnings
	shop.cash_on_hand = shop.daily_revenue
	CrewMuscleSystem.shake_down(world, crew)
	assert(shop.cash_on_hand == shop.daily_revenue, "once per day per shop")
	assert(crew.crew_earnings == held, "nothing more from anyone already paid")

	# Next day: pays again.
	world.tick = 5000 + CrewMuscleSystem.PROTECTION_COOLDOWN_TICKS
	CrewMuscleSystem.shake_down(world, crew)
	assert(shop.cash_on_hand == shop.daily_revenue - expected, "pays again next day")

	# Gang turf never pays.
	var turf_id := _first_turf(world)
	if turf_id != &"":
		var turf: BuildingData = world.entities[turf_id].get_component(ComponentNames.BUILDING)
		turf.daily_revenue = 100
		turf.cash_on_hand = 100
		crew.position = turf.position
		world.reindex_position(crew.id)
		CrewMuscleSystem.shake_down(world, crew)
		assert(turf.cash_on_hand == 100, "gang turf is off-limits")

	assert(state.law_tier == GanstoidEnums.LawTier.CLEAN, "player wasn't there -- no player heat")

	# Collect.
	var earned := crew.crew_earnings
	var cut := int(floor(earned * CrewLoyaltySystem.CREW_CUT_FRACTION))
	var cash_before := pnpc.cash
	var r := CrewMuscleSystem.toggle(world, crew.id)
	assert(r["effect"] == "muscle_collected" and r["payout"] == earned - cut, "payout minus cut")
	assert(pnpc.cash == cash_before + earned - cut and crew.cash == cut and crew.crew_earnings == 0, "cash moved")
	assert(crew.crew_role == GanstoidEnums.CrewRole.UNASSIGNED, "back to following")

	print("PHASE3_CREW_MUSCLE_VERIFY: PASS")
	quit()

func _first_civilian(world: World) -> NPCData:
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != null and not n.is_cop and not n.is_dealer and not e.has_component(ComponentNames.PLAYER_STATE):
			return n
	return null

func _first_shop(world: World) -> StringName:
	for id in world.entities:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b != null and b.daily_revenue > 0 and CrimeSystem.find_territory_gang(world, id) == null:
			return id
	return &""

func _first_turf(world: World) -> StringName:
	for id in world.entities:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b != null and CrimeSystem.find_territory_gang(world, id) != null:
			return id
	return &""
