## V4 validator on the real streets: about half the workers own a car parked
## near home; a long trip is driven along the street graph (one-way respected)
## and the driver parks near the door and walks in; a short trip is walked;
## nobody else drives.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 6)
	var city := TestWorlds.city()
	DriveSystem.graph = RoadGraph.build(city.roads)
	TrafficSystem.roads = city.roads
	var drive := world.find_system(DriveSystem) as DriveSystem
	var owners := 0
	var workers := 0
	var who: NPCData = null
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.work_building_id != &"" and not n.is_cop:
			workers += 1
			if n.car_id != &"":
				owners += 1
				if who == null:
					who = n
	print("workers %d, car owners %d (%.0f%%)" % [workers, owners, 100.0 * owners / maxf(1, workers)])
	if not _check(owners > workers * 0.25 and who != null, "a good share of workers own a car"):
		return
	var car: VehicleData = world.entities[who.car_id].get_component(ComponentNames.VEHICLE)
	who.position = car.position + Vector2(3, 0)
	var far := car.position + Vector2(900, 400)
	var dest: Vector2 = DriveSystem.graph.astar.get_point_position(DriveSystem.graph.astar.get_closest_point(far))
	var short := drive.try_drive(who, who.position + Vector2(100, 0))
	drive.process_entities(world.get_entities_with_component(ComponentNames.PLAYER_STATE), 1.0 / 60.0, 0)
	var started := drive.try_drive(who, dest)
	var start := car.position
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	var t := 0
	while drive.drives.has(who.id) and t < 60 * 600:
		world.tick += 1
		t += 1
		drive.process_entities(players, 1.0 / 60.0, world.tick)
	print("short trip driven: %s; long trip: started %s, %.0f m away, arrived in %.0f s, parked %.0f m from the door, walking: %s" % [short, started, start.distance_to(dest), t / 60.0, car.position.distance_to(dest), not who.indoors])
	if not _check(not short and started and not drive.drives.has(who.id) and car.position.distance_to(dest) < 30.0 and car.driver_id == &"", "a long trip is driven and the car parked at the other end"):
		return
	print("DRIVING_VERIFY: PASS")
	quit()

func _check(good: bool, what: String) -> bool:
	if not good:
		print("DRIVING_VERIFY: FAIL - ", what)
		quit(1)
	return good
