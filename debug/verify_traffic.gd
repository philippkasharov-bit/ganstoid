## V2 validator on the real streets: traffic fills up near the player and
## moves along the streets at city speed; a car stops for a person in front;
## a carjack gives you a stopped car; wanted and driving starts a pursuit that
## you lose by getting far enough ahead.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 4)
	TrafficSystem.roads = TestWorlds.city().roads
	var traffic := world.find_system(TrafficSystem) as TrafficSystem
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var state: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var starts := {}
	for t in 60 * 20:
		world.tick += 1
		traffic.process_entities(players, 1.0 / 60.0, world.tick)
		if t == 60:
			for id in traffic._drive:
				starts[id] = traffic._car(id).position
	var moved := 0
	var speeds := 0.0
	for id in starts:
		var c: VehicleData = traffic._car(id)
		if c != null and c.position.distance_to(starts[id]) > 40.0:
			moved += 1
		speeds += c.speed if c != null else 0.0
	print("traffic: %d cars, %d of %d moved 40 m+ in 19 s, mean speed %.1f m/s" % [traffic._drive.size(), moved, starts.size(), speeds / maxf(1, starts.size())])
	if not _check(traffic._drive.size() == TrafficSystem.CARS and moved > starts.size() * 0.6, "traffic drives the streets near you"):
		return
	var id: StringName = traffic._drive.keys()[0]
	var car: VehicleData = traffic._car(id)
	var walker := NPCData.new()
	walker.id = &"walker"
	walker.position = car.position + Vector2.from_angle(car.heading) * 6.0
	var we := Entity.new(&"walker")
	we.add_component(walker)
	world.register_entity(we)
	world.reindex_position(&"walker")
	var in_front := traffic._something_ahead(car, me)
	walker.position = car.position + Vector2.from_angle(car.heading).orthogonal() * 4.0
	world.reindex_position(&"walker")
	var beside := traffic._something_ahead(car, me)
	walker.position = car.position + Vector2.from_angle(car.heading) * 6.0
	world.reindex_position(&"walker")
	for t in 90:
		world.tick += 1
		traffic.process_entities(players, 1.0 / 60.0, world.tick)
		walker.position = car.position + Vector2.from_angle(car.heading) * 6.0   # they keep standing in its way
		world.reindex_position(&"walker")
	print("person 6 m in front seen %s, 4 m to the side seen %s; speed after 1.5 s %.1f" % [in_front, beside, car.speed])
	if not _check(in_front and not beside and car.speed < 0.5, "cars stop for someone in their lane"):
		return
	me.position = car.position + Vector2(0, 2)
	world.reindex_position(me.id)
	var jack := TrafficSystem.carjack(world, me, state, car)
	print("carjack: %s, in car %s" % [jack.get("effect"), state.vehicle_id == car.id])
	if not _check(jack.get("effect") == "car_in", "a carjack puts you in the car"):
		return
	state.law_tier = GanstoidEnums.LawTier.WARNED
	for t in 60 * 2:
		world.tick += 1
		car.speed = 15.0
		car.position += Vector2(15, 0) / 60.0   # driving away, not stopped
		me.position = car.position
		traffic.process_entities(players, 1.0 / 60.0, world.tick)
	var chased := traffic.chasing()
	car.position += Vector2(600, 0)
	me.position = car.position
	for t in 60 * 17:
		world.tick += 1
		traffic.process_entities(players, 1.0 / 60.0, world.tick)
	print("pursuit started %s, after getting 600 m ahead for 17 s: chasing %s, heat %d" % [chased, traffic.chasing(), state.law_tier])
	if not _check(chased and not traffic.chasing() and state.law_tier == 0, "a pursuit starts and can be lost"):
		return
	print("TRAFFIC_VERIFY: PASS")
	quit()

func _check(good: bool, what: String) -> bool:
	if not good:
		print("TRAFFIC_VERIFY: FAIL - ", what)
		quit(1)
	return good
