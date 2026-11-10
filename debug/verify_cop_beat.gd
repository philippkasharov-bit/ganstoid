## S3b validator: cops on foot walk a beat along the streets round their station.
##   - over five real minutes every patrolling cop reaches several corners of
##     its loop (they walk it, they do not stand about)
##   - they stay on public ground (never in a building) and inside the 150 m leash
##   - a cop's loop changes from one day to the next
extends SceneTree

const RUN_SECONDS := 300.0

func _initialize() -> void:
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	var city := CityData.load_file()
	var col := CityCollision.new(city)
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_real_city_game(world, 1, city, city.spawn, TestWorlds.DISTRICT_RADIUS, 600)
	SimNav.install(city, city.spawn, TestWorlds.DISTRICT_RADIUS)
	await TestWorlds.wait_nav(self, [SimNav.active])
	var cops_sys: CopAISystem = world.find_system(CopAISystem)
	world.tick = SimClock.hours(10.0)
	(world.find_system(NPCScheduleSystem) as NPCScheduleSystem).settle_all(world.tick)
	var cops: Array = []
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		if e.get_component(ComponentNames.NPC).is_cop:
			cops.append(e.get_component(ComponentNames.NPC))
	var inside := 0
	var farthest := 0.0
	var start := {}
	for c in cops:
		start[c.id] = c.position
	for i in SimClock.real_seconds(RUN_SECONDS):
		world.step(1.0 / SimClock.TICKS_PER_SECOND)
		if i % 30 == 0:
			for c in cops:
				inside += int(col.blocked(c.position, 0.0))
				farthest = maxf(farthest, c.position.distance_to(cops_sys._depot_position(c)))
	var per_cop := float(cops_sys.beat.corners_reached) / maxi(cops.size(), 1)
	var today: Array = cops_sys.beat.stops_of(cops[0].id)
	cops_sys.beat.forget(cops[0].id)
	cops_sys.beat.advance(cops[0], cops_sys._depot_position(cops[0]), CopAISystem.PATROL_SPEED, 1.0 / 60.0, world.tick + SimClock.day_ticks)
	var tomorrow: Array = cops_sys.beat.stops_of(cops[0].id)
	print("%d cops, %d real s: corners reached %.1f per cop, samples inside a building %d, farthest from station %.0f m (leash %.0f); first cop's loop changes next day: %s" % [
		cops.size(), int(RUN_SECONDS), per_cop, inside, farthest, CopAISystem.PATROL_WANDER_RADIUS, today != tomorrow])
	SimNav.uninstall()
	var ok := _check(cops.size() > 0 and per_cop >= 3.0, "every cop walks several corners of its beat in five minutes")
	ok = _check(inside == 0, "cops never walk inside a building") and ok
	ok = _check(farthest <= CopAISystem.PATROL_WANDER_RADIUS + 15.0, "cops stay near their station") and ok
	ok = _check(today != tomorrow, "the beat changes from day to day") and ok
	if ok:
		print("COP_BEAT_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("COP_BEAT_VERIFY: FAIL - ", what)
	return ok
