## Standalone verification harness for Phase 2 batch 10: BuildingData.
## crime_heat (generalized "patrol high crime places" trigger, replacing
## has_been_hit as CopAISystem's guard-bias source) and the raid tier it
## feeds once a RAIDABLE building's heat clears RAID_HEAT_THRESHOLD.
## Dev tool, not shipped content. Run with:
##   godot --headless --path . --script res://debug/verify_phase2_patrol_heat_and_raids.gd
##
## Covers, in order:
##   1. crime_heat only accumulates through the witnessed-and-recognized
##      path (no witness/no recognition -> no heat), and accumulates for
##      ANY crime type, not just robbery.
##   2. crime_heat decays back toward 0.0 on its own (EconomySystem).
##   3. The guard-bias patrol tier now keys off crime_heat generally, not
##      has_been_hit specifically.
##   4. A raid only ever fires on an is_raidable building once heat clears
##      RAID_HEAT_THRESHOLD, and does the exact "both at once" thing Phil
##      chose: heavier patrol AND (if it's gang turf) a real gang-cash/
##      player-standing cost -- never anything that touches the player
##      directly outside the pre-existing witnessed+recognized path.
##   5. A non-raidable building (ordinary business) never raids no matter
##      how hot it gets -- guard tier only.
extends SceneTree

var _reports := 0

func _count_report(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == GanstoidEvents.CRIME_WITNESSED:
		_reports += 1

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	world.event_bus.subscribe(_count_report)

	var player_entity: Entity = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0]
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)

	# --- Part 1: crime_heat only moves via witnessed-and-recognized crimes,
	# for any crime type -- not pickpocket-only, not proximity-only.
	var heat_building_id := _find_a_revenue_building(world)
	assert(heat_building_id != &"", "worldgen should produce at least one revenue-earning building")
	var heat_building: BuildingData = world.entities[heat_building_id].get_component(ComponentNames.BUILDING)
	assert(heat_building.crime_heat == 0.0, "a fresh building should start with zero crime_heat")

	var victim_id := _find_a_civilian(world, player_entity.id)
	assert(victim_id != &"", "need at least one civilian NPC to pickpocket")
	var victim_npc: NPCData = world.entities[victim_id].get_component(ComponentNames.NPC)
	victim_npc.cash = 50
	victim_npc.position = heat_building.position
	world.reindex_position(victim_id)
	victim_npc.recognition_chance = 0.0  # unrecognized witness -- should NOT bump heat
	player_npc.position = heat_building.position
	world.reindex_position(PlayerFactory.PLAYER_ENTITY_ID)

	var unwitnessed := CrimeSystem.commit_crime(world, GanstoidEnums.CrimeType.PICKPOCKET, victim_id)
	assert(unwitnessed.get("ok", false), "pickpocket should still succeed mechanically even when nobody recognizes it")
	# Seeing the crime gives the victim a fresh (severity-sized) chance to
	# recognize you on the spot, so a report CAN legitimately happen here.
	# The real rule: crime_heat moves if and only if a witness reported.
	assert((heat_building.crime_heat == 0.0) == (_reports == 0), "crime_heat moves only when a recognized witness reports -- no free pass around the evidence gate")
	heat_building.crime_heat = 0.0  # reset so the forced-recognition checks below start clean

	victim_npc.cash = 50
	victim_npc.recognition_chance = 1.0  # forced deterministic recognition, same trick verify_phase1.gd uses
	var witnessed := CrimeSystem.commit_crime(world, GanstoidEnums.CrimeType.PICKPOCKET, victim_id)
	assert(witnessed.get("ok", false), "pickpocket should succeed")
	assert(heat_building.crime_heat > 0.0, "a witnessed-and-recognized crime of ANY type (not just robbery) must bump the nearest building's crime_heat")
	var heat_after_one: float = heat_building.crime_heat
	print("crime_heat after one witnessed pickpocket: %.3f" % heat_after_one)

	# A second witnessed crime should bump it further (diminishing returns,
	# not a hard cap at the first bump's value).
	victim_npc.cash = 50
	CrimeSystem.commit_crime(world, GanstoidEnums.CrimeType.PICKPOCKET, victim_id)
	assert(heat_building.crime_heat > heat_after_one, "a second witnessed crime should push crime_heat higher still")
	print("crime_heat after two witnessed pickpockets: %.3f" % heat_building.crime_heat)

	# --- Part 2: crime_heat decays back toward 0.0 on its own.
	heat_building.crime_heat = 0.8
	for i in 3000:
		world.step(1.0 / 60.0)
	print("crime_heat after 3000 idle ticks (started at 0.8): %.3f" % heat_building.crime_heat)
	assert(heat_building.crime_heat < 0.1, "crime_heat should have decayed back down close to zero after 3000 idle ticks, same cadence as reputation/standing decay")

	# Part 1's witnessed pickpockets broadcast CRIME_WITNESSED, which alerts
	# any cop within CopAISystem.BROADCAST_RADIUS of heat_building -- clear
	# that off before testing patrol behavior below, same "a raid/guard test
	# isn't an arrest test" isolation the rest of this file relies on. One
	# step is enough: every alerted cop's own _advance_alert branch checks
	# law_tier == CLEAN and stands itself down the same tick it sees this.
	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	player_state.law_tier = GanstoidEnums.LawTier.CLEAN
	world.step(1.0 / 60.0)

	# --- Part 3: the generalized guard-bias tier keys off crime_heat, not
	# has_been_hit. A building that's never been robbed but has enough
	# crime_heat (set directly here, isolating the CopAISystem behavior
	# from the witness-roll machinery already proven in Part 1) should
	# still pull a nearby cop's patrol in tight.
	#
	# Uses a freshly spawned test cop, not a seeded one -- a seeded cop may
	# already carry stale WanderBehavior drift-target state from the
	# single flush tick above (anchored at whatever ITS original depot
	# was), and that state persists across a home_building_id/position
	# change since it lives in CopAISystem's own per-mover dictionaries,
	# not on NPCData. A brand-new cop has never been ticked, so there is
	# nothing stale to carry forward.
	var guard_building_id := _find_a_revenue_building(world, heat_building_id)
	assert(guard_building_id != &"", "need a second revenue building distinct from Part 1/2's")
	var guard_building: BuildingData = world.entities[guard_building_id].get_component(ComponentNames.BUILDING)
	assert(not guard_building.has_been_hit, "this building should never have been robbed -- proving the guard tier no longer depends on that flag")
	guard_building.crime_heat = 0.6  # above PATROL_BIAS_HEAT_THRESHOLD (0.3), with margin to survive the short step window below

	var cop_npc := _make_test_cop(world, &"test_cop_guard", guard_building_id)
	var max_dist_from_guard_building := 0.0
	for i in 300:  # 5 sim-seconds -- short enough that 0.6 decaying stays well above the 0.3 threshold throughout (see EconomySystem.CRIME_HEAT_DECAY doc comment math)
		world.step(1.0 / 60.0)
		max_dist_from_guard_building = maxf(max_dist_from_guard_building, cop_npc.position.distance_to(guard_building.position))
	print("max distance from a crime_heat=0.6 building (never robbed) over 300 ticks: %.1f (guarded radius: %.1f)" % [max_dist_from_guard_building, CopAISystem.GUARDED_WANDER_RADIUS])
	assert(max_dist_from_guard_building <= CopAISystem.GUARDED_WANDER_RADIUS + 1.0, "a cop whose depot sits on a hot-but-never-robbed building must still tighten to the guarded radius")

	# --- Part 4: the raid tier, gang-turf case -- "both at once."
	var gang_pick := _find_a_gang_territory_building(world)
	assert(gang_pick.get("building_id", &"") != &"", "GangSeeder should have claimed at least one illegal-front lot as gang territory")
	var raid_building_id: StringName = gang_pick["building_id"]
	var gang_id: StringName = gang_pick["gang_id"]
	var raid_building: BuildingData = world.entities[raid_building_id].get_component(ComponentNames.BUILDING)
	assert(raid_building.is_raidable, "an illegal-front lot claimed as gang territory should be flagged is_raidable at worldgen")
	var gang_entity: Entity = world.entities[gang_id]
	var gang: GangData = gang_entity.get_component(ComponentNames.GANG)
	var gang_cash_before: int = gang.cash
	var standing_before: float = player_state.gang_standing.get(gang_id, 0.5)
	var law_tier_before: GanstoidEnums.LawTier = player_state.law_tier
	var player_cash_before: int = player_npc.cash

	raid_building.crime_heat = CopAISystem.RAID_HEAT_THRESHOLD + 0.05
	_make_test_cop(world, &"test_cop_raid", raid_building_id)

	world.step(1.0 / 60.0)  # CopAISystem runs every HOT tick -- one is enough to trigger the raid
	print("raid_building crime_heat right after the raid: %.3f (was %.3f)" % [raid_building.crime_heat, CopAISystem.RAID_HEAT_THRESHOLD + 0.05])
	assert(raid_building.crime_heat < CopAISystem.PATROL_BIAS_HEAT_THRESHOLD, "a raid must relieve the building's own crime_heat hard enough to drop it below even the patrol-bias threshold, so it can't re-trigger next tick")
	assert(gang.cash == gang_cash_before - int(round(gang_cash_before * CopAISystem.RAID_GANG_CASH_PENALTY_FRACTION)), "a raid on gang turf must drain the owning gang's cash by exactly RAID_GANG_CASH_PENALTY_FRACTION")
	var expected_standing: float = standing_before - standing_before * CopAISystem.RAID_STANDING_PENALTY
	assert(is_equal_approx(player_state.gang_standing.get(gang_id, 0.5), expected_standing), "a raid on gang turf must cost the player exactly RAID_STANDING_PENALTY of their prior standing with that gang")
	assert(player_state.law_tier == law_tier_before, "a raid must never touch the player's own law_tier -- the player is never directly punished for a raid")
	assert(player_npc.cash == player_cash_before, "a raid must never directly touch the player's cash")
	print("gang cash %d -> %d, standing %.3f -> %.3f" % [gang_cash_before, gang.cash, standing_before, player_state.gang_standing.get(gang_id, 0.5)])

	# Self-regulating: stepping further ticks must not drain the gang a
	# second time off the same already-relieved heat.
	var gang_cash_after_one_raid: int = gang.cash
	for i in 60:
		world.step(1.0 / 60.0)
	assert(gang.cash == gang_cash_after_one_raid, "a raid is a one-time event -- heat relief must prevent it from re-firing every tick")

	# --- Part 4b: the raid tier, non-gang-turf case -- heavier patrol only,
	# no gang/player cost, since there's no gang to charge.
	var solo_raid_building_id := _find_a_raidable_non_gang_building(world)
	if solo_raid_building_id != &"":
		var solo_building: BuildingData = world.entities[solo_raid_building_id].get_component(ComponentNames.BUILDING)
		solo_building.crime_heat = CopAISystem.RAID_HEAT_THRESHOLD + 0.05
		_make_test_cop(world, &"test_cop_solo_raid", solo_raid_building_id)
		var solo_player_cash_before: int = player_npc.cash
		var solo_law_tier_before: GanstoidEnums.LawTier = player_state.law_tier
		world.step(1.0 / 60.0)
		assert(solo_building.crime_heat < CopAISystem.PATROL_BIAS_HEAT_THRESHOLD, "a raid on a non-gang raidable building should still relieve its own heat")
		assert(player_npc.cash == solo_player_cash_before, "a raid with no owning gang must still never touch the player's cash")
		assert(player_state.law_tier == solo_law_tier_before, "a raid with no owning gang must still never touch the player's law_tier")
		print("non-gang raidable building raided cleanly -- no gang/player side effects")

	# --- Part 5: a non-raidable building never raids, however hot it gets --
	# the is_raidable gate holds even past RAID_HEAT_THRESHOLD.
	var ordinary_building_id := _find_a_revenue_building(world, heat_building_id, guard_building_id)
	assert(ordinary_building_id != &"", "need a third ordinary revenue building distinct from Parts 1-3's")
	var ordinary_building: BuildingData = world.entities[ordinary_building_id].get_component(ComponentNames.BUILDING)
	assert(not ordinary_building.is_raidable, "an ordinary revenue building (not ILLEGAL_FRONT/SAFEHOUSE) must not be is_raidable")
	ordinary_building.crime_heat = CopAISystem.RAID_HEAT_THRESHOLD + 0.1
	var ordinary_cop_npc := _make_test_cop(world, &"test_cop_ordinary", ordinary_building_id)
	var heat_before_tick: float = ordinary_building.crime_heat
	world.step(1.0 / 60.0)
	assert(ordinary_building.crime_heat >= heat_before_tick * 0.99, "a non-raidable building's heat must NOT get the raid's heavy relief -- only its own slow decay, not a one-tick drop")
	assert(ordinary_cop_npc.position.distance_to(ordinary_building.position) <= CopAISystem.GUARDED_WANDER_RADIUS + 1.0, "a non-raidable building this hot should still get the guard-bias tier, just never a raid")

	print("PHASE2_PATROL_HEAT_AND_RAIDS_VERIFY: PASS")
	quit()

func _find_a_revenue_building(world: World, exclude_a: StringName = &"", exclude_b: StringName = &"") -> StringName:
	for id in world.entities:
		if id == exclude_a or id == exclude_b:
			continue
		var entity: Entity = world.entities[id]
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building != null and building.daily_revenue > 0 and building.cash_on_hand > 0 and not building.is_raidable:
			return id
	return &""

## Spawns a brand-new cop NPC entity, parked exactly on building_id's
## position with its home_building_id pointed there -- see Part 3's doc
## comment for why a fresh entity, not a reused seeded cop, is what keeps
## these patrol/raid checks deterministic (no stale WanderBehavior drift
## state from ticks that ran before this test picked it).
func _make_test_cop(world: World, cop_id: StringName, home_building_id: StringName) -> NPCData:
	var building: BuildingData = world.entities[home_building_id].get_component(ComponentNames.BUILDING)
	var npc := NPCData.new()
	npc.id = cop_id
	npc.is_cop = true
	npc.home_building_id = home_building_id
	npc.position = building.position
	var entity := Entity.new(cop_id)
	entity.add_component(npc)
	world.register_entity(entity)
	return npc

func _find_a_civilian(world: World, exclude_id: StringName) -> StringName:
	for id in world.entities:
		if id == exclude_id:
			continue
		var entity: Entity = world.entities[id]
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and not npc.is_cop:
			return id
	return &""

## Returns {"gang_id": ..., "building_id": ...} for the first gang found
## with at least one claimed territory building.
func _find_a_gang_territory_building(world: World) -> Dictionary:
	for entity in world.get_entities_with_component(ComponentNames.GANG).values():
		var gang: GangData = entity.get_component(ComponentNames.GANG)
		if gang.territory_building_ids.size() > 0:
			return {"gang_id": gang.id, "building_id": gang.territory_building_ids[0]}
	return {}

## An is_raidable building (ILLEGAL_FRONT/SAFEHOUSE) that no gang claims as
## territory -- GangSeeder only ever claims a subset of illegal fronts, and
## never touches SAFEHOUSE lots at all, so this should usually find one.
func _find_a_raidable_non_gang_building(world: World) -> StringName:
	for id in world.entities:
		var entity: Entity = world.entities[id]
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building == null or not building.is_raidable:
			continue
		if CrimeSystem.find_territory_gang(world, id) == null:
			return id
	return &""
