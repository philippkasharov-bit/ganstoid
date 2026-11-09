## Batch 22: roster text shows each crew member's name, job, loyalty and
## holdings; empty-crew hint; civilians now have names, deterministically.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	var state: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)

	assert(CrewRoster.format_roster(world, state).contains("press R"), "empty-crew hint")

	var civ: NPCData = world.entities[&"npc_0"].get_component(ComponentNames.NPC)
	assert(civ.display_name == PopulationSeeder.civilian_name(0) and civ.display_name != "", "civilians have names")
	assert(PopulationSeeder.civilian_name(0) != PopulationSeeder.civilian_name(1), "names vary")

	civ.is_crew = true
	civ.crew_role = GanstoidEnums.CrewRole.DEALER
	civ.loyalty = 0.62
	civ.crew_stash = 3
	civ.crew_earnings = 24
	state.crew_ids.append(civ.id)
	var text := CrewRoster.format_roster(world, state)
	print(text)
	for part in [civ.display_name, "dealing", "loyalty 62%", "3 weed", "$24", "(1/5)"]:
		assert(text.contains(part), "roster shows " + part)

	# Same seed -> same names (no worldgen drift).
	var world2 := World.new()
	SystemRegistry.register_all(world2)
	TestWorlds.real_city(world2)
	assert(world2.entities[&"npc_5"].get_component(ComponentNames.NPC).display_name == world.entities[&"npc_5"].get_component(ComponentNames.NPC).display_name, "deterministic")

	print("PHASE3_CREW_ROSTER_VERIFY: PASS")
	quit()
