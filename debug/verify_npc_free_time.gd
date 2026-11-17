## NB2c validator: free time by the shared brain (NPCFreeTime, GameRules.brain).
##   - the switch is off by default, and with it off nobody gets a mind (old path)
##   - with it on, a day of free time: people go out, the picks are varied,
##     needs are filled by what they did, habits are kept, nobody is stranded
##   - the same person, day and quarter hour plan the same trip
##   - a stay on the stoop holds them at their own door
##   - 6,000 minds keep the save small (NB2d: under 1 MB)
extends SceneTree

const POPULATION := 600
const SEED := 4242

func _initialize() -> void:
	var saved := SimClock.day_ticks
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS   # real clock: walks take real time, a fast clock makes them look too long
	var city := CityData.load_file()
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_real_city_game(world, 1, city, city.spawn, TestWorlds.DISTRICT_RADIUS, POPULATION)
	SimNav.install(city, city.spawn, TestWorlds.DISTRICT_RADIUS)
	await TestWorlds.wait_nav(self, [SimNav.active])
	var sched: NPCScheduleSystem = world.find_system(NPCScheduleSystem)
	var ok := _check_off(world, sched)
	ok = ok and _check_on(world, sched)
	ok = ok and _check_same_plan(world, sched)
	SimNav.uninstall()
	SimClock.day_ticks = saved
	ok = ok and _check_save_size()
	if ok:
		print("NPC_FREE_TIME_VERIFY: PASS")
	quit(0 if ok else 1)

func _run(world: World, sched: NPCScheduleSystem, from_hour: float, hours: float) -> int:
	world.tick = SimClock.hours(from_hour)
	sched.settle_all(world.tick)
	var started := sched.outings_started
	for i in SimClock.hours(hours):
		world.step(1.0 / SimClock.TICKS_PER_SECOND)
	return sched.outings_started - started

func _check_off(world: World, sched: NPCScheduleSystem) -> bool:
	var outings := _run(world, sched, 11.0, 2.0)
	var minds := world.get_entities_with_component(ComponentNames.NPC_MIND).size()
	print("switch off: %d outings in 2 h, %d minds" % [outings, minds])
	return _check(not GameRules.brain(world), "the switch is off by default") \
		and _check(outings > 0 and minds == 0, "with the switch off, the old free time runs and nobody gets a mind")

func _check_on(world: World, sched: NPCScheduleSystem) -> bool:
	GameRules.install(world, 1, 1).npc_brain = true
	var stranded := sched.street.stranded
	var outings := _run(world, sched, 9.0, 10.0)
	var minds := world.get_entities_with_component(ComponentNames.NPC_MIND)
	var picks: Dictionary = sched.free_time.picks
	var habits := 0
	var food := 0.0
	for e in minds.values():
		var m: NPCMindData = e.get_component(ComponentNames.NPC_MIND)
		habits += 1 if m.habit_slots.size() == NPCMind.HABIT_SLOTS else 0
		food += NPCMind.drives_now(e.id, m, world.tick)[GanstoidEnums.MindDrive.FOOD]
	var total := 0
	for k in picks:
		total += picks[k]
	print("switch on, 09:00-19:00: %d trips out, %d choices %s, %d minds, %d with habits, mean food %.2f, newly stranded %d" % [
		outings, total, picks, minds.size(), habits, food / maxf(1.0, minds.size()), sched.street.stranded - stranded])
	var biggest: int = picks.values().max() if not picks.is_empty() else 0
	return _check(outings >= 100, "people go out (100+ trips in 10 hours)") \
		and _check(picks.size() >= 6 and biggest < total * 0.5, "the day is varied (6+ activities, none over half)") \
		and _check(habits >= minds.size() / 2 and minds.size() > 0, "most people who chose keep a habit (the rest had no time before work)") \
		and _check(food / maxf(1.0, minds.size()) > 0.25, "eating keeps people fed") \
		and _check(sched.street.stranded - stranded <= outings / 50, "nobody gets stranded")

func _check_same_plan(world: World, sched: NPCScheduleSystem) -> bool:
	var npc: NPCData
	for e in world.get_entities_with_component(ComponentNames.NPC_MIND).values():
		npc = e.get_component(ComponentNames.NPC)
		break
	var home := ActivityPlaces.home_of(world, npc)
	var a := sched.free_time.plan(world, npc, home, world.tick)
	var b := sched.free_time.plan(world, npc, home, world.tick)
	var linger := sched.free_time._trip(&"hang_out", home, home, NPCFreeTime.rng_for(npc.id, world.tick))
	print("plan now: %s; stoop: hold %d ticks, legs %s" % [a.get("activity", "nothing"), linger["hold"], linger["legs"]])
	return _check(str(a) == str(b), "the same person and moment plan the same trip") \
		and _check(linger["hold"] > 0 and linger["legs"].is_empty(), "the stoop holds them at their own door")

func _check_save_size() -> bool:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, SEED)
	var base := var_to_str(SaveGame.snapshot(w, SEED)).length()
	var mind := NPCMind.make(w.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC), w.tick)
	mind.habit_slots.resize(NPCMind.HABIT_SLOTS)
	mind.habit_slots[2] = "eat"
	var one := var_to_str({ComponentNames.NPC_MIND: MindPack.pack(mind)}).length()
	var kb := one * 6000 / 1024
	print("save: %d KB now; one mind %d bytes, so 6,000 minds add about %d KB" % [base / 1024, one, kb])
	return _check(kb < 1024, "6,000 minds add under 1 MB to the save")

func _check(good: bool, what: String) -> bool:
	if not good:
		print("NPC_FREE_TIME_VERIFY: FAIL - ", what)
	return good
