## Standalone verification harness for Phase 2 batch 9: the minimal
## gang-job action (CrimeSystem.do_gang_job) built on top of batch 8's
## GangData seed and gang_standing tracking. Dev tool, not shipped
## content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_gang_jobs.gd
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)

	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)

	# --- Part 1: territory lookup resolves the right gang, and resolves
	# nothing at all for an ordinary building.
	var gangs := world.get_entities_with_component(ComponentNames.GANG)
	var territory_building_id: StringName = &""
	var owning_gang: GangData = null
	for entity in gangs.values():
		var gang: GangData = entity.get_component(ComponentNames.GANG)
		if not gang.territory_building_ids.is_empty():
			territory_building_id = gang.territory_building_ids[0]
			owning_gang = gang
			break
	assert(territory_building_id != &"", "at least one gang should have claimed territory to run this test")
	var found_entity := CrimeSystem.find_territory_gang(world, territory_building_id)
	assert(found_entity != null and found_entity.get_component(ComponentNames.GANG).id == owning_gang.id, "find_territory_gang should resolve the correct owning gang")

	var non_territory_id: StringName = &""
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building != null and CrimeSystem.find_territory_gang(world, id) == null:
			non_territory_id = id
			break
	assert(non_territory_id != &"", "need at least one ordinary building to check the negative case")
	print("territory lookup correct: %s -> %s, an ordinary building resolves to no gang" % [territory_building_id, owning_gang.id])

	# --- Part 2: payout multiplier formula, same landmark shape as batch
	# 7/8's price multiplier checks.
	assert(is_equal_approx(CrimeSystem._gang_job_multiplier(0.5), 1.0), "neutral standing must price the job at exactly base payout")
	assert(is_equal_approx(CrimeSystem._gang_job_multiplier(1.0), 1.0 + CrimeSystem.GANG_JOB_STANDING_SWING), "max standing should give the best payout multiplier")
	print("gang job payout multiplier formula checks out at the neutral/max landmarks")

	# --- Part 3: too-far refusal.
	var territory_building: BuildingData = world.entities[territory_building_id].get_component(ComponentNames.BUILDING)
	player_npc.position = territory_building.position + Vector2(9999, 0)
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	var far_result := CrimeSystem.do_gang_job(world, territory_building_id)
	assert(not far_result.get("ok", false) and far_result.get("reason", "") == "too_far", "a gang job attempt from far away must be refused as too_far")

	# --- Part 4: a successful job at neutral standing pays exactly base,
	# drains the gang's own cash pool by exactly that, credits the player
	# by exactly that, and raises standing with that gang.
	player_npc.position = territory_building.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)
	var cash_before := player_npc.cash
	var gang_cash_before := owning_gang.cash
	var result := CrimeSystem.do_gang_job(world, territory_building_id)
	assert(result.get("ok", false), "a gang job in range against a funded gang should succeed")
	assert(result["payout"] == CrimeSystem.GANG_JOB_BASE_PAYOUT, "neutral standing should pay exactly the base payout")
	assert(player_npc.cash == cash_before + result["payout"], "player cash must rise by exactly the payout")
	assert(owning_gang.cash == gang_cash_before - result["payout"], "the gang's own cash pool must drain by exactly the payout")
	var standing_after_one: float = player_state.gang_standing.get(owning_gang.id, 0.5)
	assert(standing_after_one > 0.5, "a completed gang job should raise standing with that gang")
	print("standing with %s after 1 job: %.3f, payout: %d" % [owning_gang.id, standing_after_one, result["payout"]])

	# --- Part 5: repeated jobs keep raising standing further.
	for i in 10:
		CrimeSystem.do_gang_job(world, territory_building_id)
	var standing_after_eleven: float = player_state.gang_standing.get(owning_gang.id, 0.5)
	assert(standing_after_eleven > standing_after_one, "repeated jobs should keep raising standing")
	print("standing with %s after 11 jobs: %.3f" % [owning_gang.id, standing_after_eleven])

	# --- Part 6: the gang's cash pool drains to exactly zero (never
	# negative, since the payout is capped by what's left), and a job
	# against a broke gang is then refused rather than overdrawing it.
	var guard := 0
	while owning_gang.cash > 0 and guard < 50:
		CrimeSystem.do_gang_job(world, territory_building_id)
		guard += 1
	assert(owning_gang.cash == 0, "the gang's cash pool should be driveable to exactly zero, never negative")
	var broke_result := CrimeSystem.do_gang_job(world, territory_building_id)
	assert(not broke_result.get("ok", false) and broke_result.get("reason", "") == "gang_broke", "a job against a broke gang must be refused as gang_broke")
	print("gang cash pool correctly drains to exactly zero, then refuses further jobs")

	print("PHASE2_GANG_JOBS_VERIFY: PASS")
	quit()
