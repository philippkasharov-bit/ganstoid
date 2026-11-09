## Regression for the "wave from the corner" bug: every NPC must start the
## game at a real place in the city -- civilians and dealers at their home,
## cops at their depot -- never stacked at the world origin.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)
	var at_origin := 0
	var not_home := 0
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n == null or e.has_component(ComponentNames.PLAYER_STATE):
			continue
		if n.position == Vector2.ZERO:
			at_origin += 1
		var home: BuildingData = world.entities[n.home_building_id].get_component(ComponentNames.BUILDING)
		if n.position != home.position:
			not_home += 1
	print("npcs at origin: %d, not at home: %d" % [at_origin, not_home])
	assert(at_origin == 0, "nobody spawns at the map corner")
	assert(not_home == 0, "everybody starts at their own home / depot")
	print("SPAWN_POSITIONS_VERIFY: PASS")
	quit()
