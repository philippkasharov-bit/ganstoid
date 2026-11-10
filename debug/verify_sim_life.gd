## S2 validator: the street has a life beyond the commute, and nobody walks like
## a script.
##   1. Free time: over an afternoon and a late evening on the real clock, people
##      set out on errands and promenades; there are strollers out walking alone,
##      people inside shops, and after bedtime only the night owls are left.
##   2. Routes vary: most people with a real commute have more than one way to
##      walk it across ten days; creatures of habit have exactly one.
##   3. Days off happen, at about the intended rate.
##   4. Two people walking the same trip do not walk the same line, and neither
##      line goes through a building.
extends SceneTree

const POPULATION := 600
const AFTERNOON_REAL_MIN := 12.0
const NIGHT_REAL_MIN := 8.0

func _initialize() -> void:
	var saved := SimClock.day_ticks
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	var city := CityData.load_file()
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_real_city_game(world, 1, city, city.spawn, TestWorlds.DISTRICT_RADIUS, POPULATION)
	SimNav.install(city, city.spawn, TestWorlds.DISTRICT_RADIUS)
	await TestWorlds.wait_nav(self, [SimNav.active])
	var sched: NPCScheduleSystem = world.find_system(NPCScheduleSystem)
	var ok := _free_time(world, sched)
	ok = _night(world, sched) and ok
	ok = _routes_vary(world) and ok
	ok = _days_off(world) and ok
	ok = _own_line(world, city) and ok
	SimNav.uninstall()
	SimClock.day_ticks = saved
	if ok:
		print("SIM_LIFE_VERIFY: PASS")
	quit(0 if ok else 1)

func _run(world: World, sched: NPCScheduleSystem, from_hour: float, real_minutes: float) -> Dictionary:
	world.tick = SimClock.hours(from_hour)
	sched.settle_all(world.tick)
	var started := sched.outings_started
	var most := {"strolling": 0, "in_shops": 0, "outside": 0}
	for i in SimClock.real_seconds(real_minutes * 60.0):
		world.step(1.0 / SimClock.TICKS_PER_SECOND)
		if i % 600 == 0:
			most["strolling"] = maxi(most["strolling"], sched.street.pace_now.size())
			most["in_shops"] = maxi(most["in_shops"], sched.visiting_count())
			most["outside"] = maxi(most["outside"], sched.street.outside.size())
	most["outings"] = sched.outings_started - started
	return most

func _free_time(world: World, sched: NPCScheduleSystem) -> bool:
	var seen := _run(world, sched, 12.0, AFTERNOON_REAL_MIN)
	print("12:00 + %d real min: outings started %d, most strolling at once %d, most inside shops %d, most on the street %d" % [
		int(AFTERNOON_REAL_MIN), seen["outings"], seen["strolling"], seen["in_shops"], seen["outside"]])
	var ok := _check(seen["outings"] >= 30, "people go out in their free time (at least 30 outings in an afternoon stretch)")
	ok = _check(seen["strolling"] >= 5, "at least 5 people are out for a walk at once") and ok
	return _check(seen["in_shops"] >= 3, "people visit businesses") and ok

func _night(world: World, sched: NPCScheduleSystem) -> bool:
	var seen := _run(world, sched, 23.2, NIGHT_REAL_MIN)
	var owls := 0
	var others := 0
	var cut_through := 0
	for npc in sched.street.outside:
		if sched.street.pace_now.has(npc.id):
			if NPCOutings.is_night_owl(npc.id):
				owls += 1
			else:
				others += 1
		cut_through += int(NPCRoutine.layer_at(npc, world.tick) == "full" and not npc.is_dealer)
	print("23:12 + %d real min: outings started %d, strolling now: night owls %d, others %d, most strolling at once %d; walkers cutting through private ground %d" % [
		int(NIGHT_REAL_MIN), seen["outings"], owls, others, seen["strolling"], cut_through])
	var ok := _check(seen["strolling"] >= 1, "somebody is out walking alone late at night")
	return _check(others == 0, "after bedtime only night owls set out for a walk") and ok

func _commuters(world: World) -> Array:
	var out := []
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var npc: NPCData = e.get_component(ComponentNames.NPC)
		if npc.is_cop or npc.is_dealer or npc.work_building_id == &"" or not world.entities.has(npc.work_building_id):
			continue
		var home: Vector2 = world.entities[npc.home_building_id].get_component(ComponentNames.BUILDING).position
		var work: Vector2 = world.entities[npc.work_building_id].get_component(ComponentNames.BUILDING).position
		out.append([npc, home, work])
	return out

func _routes_vary(world: World) -> bool:
	var long_trips := 0
	var varied := 0
	var habit_varied := 0
	for row in _commuters(world):
		var npc: NPCData = row[0]
		if row[1].distance_to(row[2]) < NPCOutings.VIA_MIN_TRIP_M:
			continue
		long_trips += 1
		var ways := {}
		for day in 10:
			ways[NPCOutings.via(npc.id, day, row[1], row[2])] = true
		if ways.size() >= 2:
			varied += 1
			habit_varied += int(NPCOutings.unit(npc.id, 26) < NPCOutings.HABIT_SHARE)
	print("commutes over %d m: %d, with more than one way across 10 days: %d (%.0f%%), creatures of habit who varied: %d" % [
		int(NPCOutings.VIA_MIN_TRIP_M), long_trips, varied, 100.0 * varied / maxi(long_trips, 1), habit_varied])
	var ok := _check(long_trips > 20 and varied * 100 >= long_trips * 45, "at least 45% of real commutes change route from day to day")
	ok = _check(varied * 100 <= long_trips * 75, "and not everyone does: some people always go the same way") and ok
	return _check(habit_varied == 0, "creatures of habit never vary") and ok

func _days_off(world: World) -> bool:
	var days := 0
	var off := 0
	for row in _commuters(world):
		for day in 20:
			days += 1
			off += int(NPCOutings.takes_day_off(row[0].id, day))
	var share := float(off) / maxi(days, 1)
	print("days off: %.1f%% of working days" % (share * 100))
	return _check(share > 0.06 and share < 0.2, "people take a day off now and then (6-20% of days)")

## The same trip planned for different walkers: the lines differ, and none enters a building.
func _own_line(world: World, city: CityData) -> bool:
	var nav := SimNav.active
	var col := CityCollision.new(city)
	var tested := 0
	var differ := 0
	var in_wall := 0
	for row in _commuters(world).slice(0, 40):
		if row[1].distance_to(row[2]) < 60.0:
			continue
		var a: PackedVector2Array = nav._plan(row[1], row[2], "public", 0.0)["pts"]
		var b: PackedVector2Array = nav._plan(row[1], row[2], "public", SimNav.MAX_LANE_M)["pts"]
		if a.size() < 4:
			continue
		tested += 1
		differ += int(a != b)
		for p in b:
			in_wall += int(col.blocked(p, 0.0))
	print("same trip, two walkers: %d trips, lines differ on %d, points inside a building %d" % [tested, differ, in_wall])
	return _check(tested > 5 and differ * 10 >= tested * 8 and in_wall == 0, "walkers keep their own line and stay out of walls")

func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("SIM_LIFE_VERIFY: FAIL - ", what)
	return ok
