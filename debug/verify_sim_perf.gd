## S1 validator: the NPC simulation is realistic and cheap at game scale.
## Runs the real city with the GAME's population on the REAL clock (1 game day =
## 1 real hour) at three times of day, one real minute each:
##   03:00  the streets are empty: nearly everyone is indoors, and the sim idles
##   08:00  rush hour: the busiest minute of the day must still fit the frame
##   11:00  working day: most people with a job are at work, indoors
## A sim tick has 16.6 ms; the sim may use a fraction of that on average and must
## never eat a whole frame in one tick.
extends SceneTree

const POPULATION := 600          # = WorldDriver.GAME_POPULATION (PF3: SIM_POP=1500 overrides, for stress runs)
const TICKS := 3600              # one real minute
const AVG_BUDGET_MS := {3.0: 1.0, 8.0: 2.5, 11.0: 1.5}   # measured 0.3 / 0.8 / 0.5 in the sandbox
const WORST_TICK_MS := 10.0   # PF1: was 16; long routes no longer plan on the tick

func _initialize() -> void:
	var saved := SimClock.day_ticks
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	var city := CityData.load_file()
	var ok := true
	for hour in [3.0, 8.0, 11.0]:
		var world := World.new()
		SystemRegistry.register_all(world)
		WorldGenerator.generate_real_city_game(world, 1, city, city.spawn, TestWorlds.DISTRICT_RADIUS, int(OS.get_environment("SIM_POP")) if OS.has_environment("SIM_POP") else POPULATION)
		SimNav.install(city, city.spawn, TestWorlds.DISTRICT_RADIUS)
		await TestWorlds.wait_nav(self, [SimNav.active])
		world.tick = SimClock.hours(hour)
		(world.find_system(NPCScheduleSystem) as NPCScheduleSystem).settle_all(world.tick)
		for i in SimClock.real_seconds(20):
			world.step(1.0 / SimClock.TICKS_PER_SECOND)
		world.profiling = true   # PF1: which system makes the worst tick
		var worst := 0
		var over := 0   # PF1: ticks over 4 ms (a quarter frame): spikes, not machine noise
		var t0 := Time.get_ticks_usec()
		for i in TICKS:
			var t1 := Time.get_ticks_usec()
			world.step(1.0 / SimClock.TICKS_PER_SECOND)
			worst = maxi(worst, Time.get_ticks_usec() - t1)
			over += 1 if Time.get_ticks_usec() - t1 > 4000 else 0
		var avg_ms := (Time.get_ticks_usec() - t0) / 1000.0 / TICKS
		var c := _count(world)
		print("%02d:00  %.2f ms/tick avg, worst tick %.1f ms | civilians %d: indoors %d, on the street %d | employed %d, of them at their workplace %d | routes planned %d (navmesh %d)" % [
			int(hour), avg_ms, worst / 1000.0, c["people"], c["indoors"], c["people"] - c["indoors"], c["employed"], c["at_work"], SimNav.active.plans_made, SimNav.active.plans_routed])
		var top: Array = world.slowest_usec.keys()
		top.sort_custom(func(a, b): return world.slowest_usec[a] > world.slowest_usec[b])
		print("       ticks over 4 ms: %d of %d" % [over, TICKS])
		print("       slowest systems: %s" % ", ".join(top.slice(0, 4).map(func(k): return "%s %.1f ms" % [k, world.slowest_usec[k] / 1000.0])))
		print("       slowest route plan %.1f ms (%s)" % [SimNav.active.slowest_plan_usec / 1000.0, SimNav.active.slowest_plan_what])
		ok = _check(avg_ms <= AVG_BUDGET_MS[hour], "%02d:00 average tick within %.1f ms" % [int(hour), AVG_BUDGET_MS[hour]]) and ok
		ok = _check(worst / 1000.0 <= WORST_TICK_MS, "%02d:00 no single tick over %.0f ms" % [int(hour), WORST_TICK_MS]) and ok
		if hour == 3.0:
			ok = _check(c["indoors"] >= int(c["people"] * 0.85), "at 03:00 at least 85% of civilians are indoors") and ok
		if hour == 11.0:
			ok = _check(c["at_work"] >= int(c["employed"] * 0.6), "at 11:00 at least 60% of people with a job are at work") and ok
			ok = _check(c["at_work"] <= int(c["employed"] * 0.95), "at 11:00 not everyone is at work (evening and night shifts exist)") and ok
		SimNav.uninstall()
	SimClock.day_ticks = saved
	if ok:
		print("SIM_PERF_VERIFY: PASS")
	quit(0 if ok else 1)

func _count(world: World) -> Dictionary:
	var c := {"people": 0, "indoors": 0, "employed": 0, "at_work": 0}
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var npc: NPCData = e.get_component(ComponentNames.NPC)
		if npc.is_cop or npc.is_crew or npc.is_dealer or e.has_component(ComponentNames.PLAYER_STATE):
			continue
		c["people"] += 1
		c["indoors"] += int(npc.indoors)
		if npc.work_building_id != &"" and world.entities.has(npc.work_building_id):
			c["employed"] += 1
			var work: BuildingData = world.entities[npc.work_building_id].get_component(ComponentNames.BUILDING)
			c["at_work"] += int(npc.indoors and npc.position.distance_to(work.position) < 2.0)
	return c

func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("SIM_PERF_VERIFY: FAIL - ", what)
	return ok
