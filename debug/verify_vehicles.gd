## V1 validator: parked cars, getting in, hotwiring, driving, running someone over.
##   1. The district gets parked cars, the same ones for the same seed.
##   2. An unlocked car: F gets you in; a locked one takes the hotwire time.
##   3. Full throttle reaches city speed in seconds and the car moves that far;
##      braking stops it; F gets you out beside it.
##   4. A person in front of the bumper at speed is hurt and thrown aside.
extends SceneTree

func _initialize() -> void:
	var a := World.new()
	TestWorlds.real_city(a, 9)
	var b := World.new()
	TestWorlds.real_city(b, 9)
	var cars_a := a.get_entities_with_component(ComponentNames.VEHICLE)
	var cars_b := b.get_entities_with_component(ComponentNames.VEHICLE)
	var same := cars_a.size() == cars_b.size()
	for id in cars_a:
		same = same and cars_b.has(id) and (cars_a[id].get_component(ComponentNames.VEHICLE) as VehicleData).position == (cars_b[id].get_component(ComponentNames.VEHICLE) as VehicleData).position
	print("parked cars: %d, same for the same seed: %s" % [cars_a.size(), same])
	if not _check(cars_a.size() > 100 and same, "the district has parked cars, seeded"):
		return
	var world := World.new()
	var me := _person(world, PlayerFactory.PLAYER_ENTITY_ID, Vector2(100, 100))
	var state := PlayerStateData.new()
	world.entities[me.id].add_component(state)
	world.reindex_components(me.id)
	var open := _car(world, &"open", Vector2(102, 100), false)
	var shut := _car(world, &"shut", Vector2(100, 300), true)
	var r := VehicleSystem.use_door(world, me, state)
	if not _check(r.get("effect") == "car_in" and state.vehicle_id == &"open", "an unlocked car: straight in"):
		return
	var t := 0
	while t < 60 * 5:
		VehicleSystem.drive(world, open, 1.0, 0.0, 1.0 / 60.0)
		t += 1
	var top := open.speed
	var went := open.position.x - 102.0
	while open.speed > 0.0:
		VehicleSystem.drive(world, open, -1.0, 0.0, 1.0 / 60.0)
	var out := VehicleSystem.use_door(world, me, state)
	print("5 s full throttle: %.1f m/s, %.0f m; out: %s at %s" % [top, went, out.get("effect"), me.position])
	if not _check(top > 15.0 and went > 35.0 and out.get("effect") == "car_out" and me.position.distance_to(open.position) < 2.5, "it drives, brakes and lets you out"):
		return
	me.position = Vector2(101, 300)
	world.reindex_position(me.id)
	var start := VehicleSystem.use_door(world, me, state)
	var tries := 0
	var got := {}
	while got.is_empty() and tries < 60 * 10:
		world.tick += 1
		tries += 1
		got = VehicleSystem.advance_hotwire(world, me, state)
	print("locked car: %s, in after %.1f s" % [start.get("effect"), tries / 60.0])
	if not _check(start.get("effect") == "hotwiring" and got.get("effect") == "car_in" and absf(tries / 60.0 - VehicleSystem.HOTWIRE_S) < 0.1, "a locked car takes the hotwire time"):
		return
	var walker := _person(world, &"walker", shut.position + Vector2(8, 0))
	shut.speed = 12.0
	var hit := {}
	for k in 60:
		var o := VehicleSystem.drive(world, shut, 0.5, 0.0, 1.0 / 60.0)
		if o.has("hit"):
			hit = o["hit"]
			break
	print("ran into a walker at speed: %s, their health %.2f, bleeding %s" % [hit.keys(), walker.health, walker.bleeding])
	if not _check(hit.get("hit_id") == &"walker" and walker.health < 0.4, "a person hit at speed is badly hurt"):
		return
	# V3: cars are solid
	var a2 := _car(world, &"a2", Vector2(500, 500), false)
	var b2 := _car(world, &"b2", Vector2(506, 500), false)
	a2.speed = 10.0
	var crash := {}
	for k in 60:
		crash = VehicleSystem.drive(world, a2, 0.0, 0.0, 1.0 / 60.0)
		if crash.has("hit_car"):
			break
	print("car into car: hit %s, front car pushed to %.1f, dents %.2f / %.2f" % [crash.get("hit_car"), b2.position.x, a2.damage, b2.damage])
	if not _check(crash.get("hit_car") == &"b2" and b2.position.x > 506.0 and a2.damage > 0.0 and a2.position.x < 503.0, "cars do not drive through each other"):
		return
	print("VEHICLES_VERIFY: PASS")
	quit()

func _car(world: World, id: StringName, at: Vector2, locked: bool) -> VehicleData:
	var c := VehicleData.new()
	c.id = id
	c.position = at
	c.locked = locked
	var e := Entity.new(id)
	e.add_component(c)
	world.register_entity(e)
	return c

func _person(world: World, id: StringName, at: Vector2) -> NPCData:
	var e := Entity.new(id)
	var n := NPCData.new()
	n.id = id
	n.position = at
	e.add_component(n)
	world.register_entity(e)
	world.reindex_position(id)
	return n

func _check(good: bool, what: String) -> bool:
	if not good:
		print("VEHICLES_VERIFY: FAIL - ", what)
		quit(1)
	return good
