## S3a validator: people do not walk through each other near the player.
##   1. 40 people dropped on top of each other on open ground spread out to a
##      body's width within a couple of seconds, and the player is never moved.
##   2. In the real sim (evening), 30 people out walking are put on one sidewalk
##      spot beside the player and carry on to wherever they were going: with the
##      crowd rule they are apart within 2 s and stay apart; without it they walk
##      on in a clump. Nobody is pushed into a building, and it costs little.
extends SceneTree

const SAMPLE_EVERY := 6
const RUN_TICKS := 3600   # one real minute

func _initialize() -> void:
	var ok := _spreads_out()
	ok = await _in_the_city() and ok
	if ok:
		print("CROWD_VERIFY: PASS")
	quit(0 if ok else 1)

func _spreads_out() -> bool:
	var crowd := Crowd.new()
	var people: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 40:
		var n := NPCData.new()
		n.id = StringName("t%d" % i)
		n.position = Vector2(100, 100) + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		people.append(n)
	var player := PackedVector2Array([Vector2(100, 100)])
	for t in 180 * Crowd.EVERY_TICKS:
		crowd.separate(people, player, null)
	var closest := INF
	var to_player := INF
	for a in people.size():
		to_player = minf(to_player, people[a].position.distance_to(player[0]))
		for b in range(a + 1, people.size()):
			closest = minf(closest, people[a].position.distance_to(people[b].position))
	print("40 people dropped in a 2 m square, after 3 s: closest pair %.2f m, closest to the player %.2f m (body %.2f m)" % [closest, to_player, Crowd.BODY_M])
	return _check(closest >= Crowd.BODY_M * 0.85 and to_player >= Crowd.BODY_M * 0.85, "a dropped crowd spreads out to a body's width")

func _in_the_city() -> bool:
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	var city := CityData.load_file()
	var col := CityCollision.new(city)
	var result := {}
	for on in [false, true]:
		var world := World.new()
		SystemRegistry.register_all(world)
		WorldGenerator.generate_real_city_game(world, 1, city, city.spawn, TestWorlds.DISTRICT_RADIUS, 600)
		if SimNav.active == null:
			SimNav.install(city, city.spawn, TestWorlds.DISTRICT_RADIUS)
			await TestWorlds.wait_nav(self, [SimNav.active])
		var sched: NPCScheduleSystem = world.find_system(NPCScheduleSystem)
		sched.street.crowd.enabled = on
		world.tick = SimClock.hours(17.5)   # evening: home time plus errands and strolls
		sched.settle_all(world.tick)
		for i in 1800:
			world.step(1.0 / 60.0)
		var player: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		player.position = _busiest(sched)
		# A crowd scene: 30 of the people out walking are put on one sidewalk spot
		# beside the player, each still heading wherever they were going.
		var spot := SimNav.active.snap(player.position + Vector2(2.0, 0.0), "public")
		var moved := 0
		for npc in sched.street.outside:
			if moved < 30 and not npc.indoors:
				npc.position = spot + Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
				SimNav.active.forget(npc.id)
				moved += 1
		var overlapping := 0
		var samples := 0
		var inside := 0
		var t0 := Time.get_ticks_usec()
		for i in RUN_TICKS:
			world.step(1.0 / 60.0)
			if i % SAMPLE_EVERY == 0 and i >= 120:   # from 2 s on: time to step apart
				var near: Array = []
				for npc in sched.street.outside:
					if npc.position.distance_to(player.position) < Crowd.RANGE_M:
						near.append(npc)
						inside += int(col.blocked(npc.position, 0.0))
				overlapping += _pairs_closer(near, 0.45)
				samples += 1
		result[on] = [float(overlapping) / samples, inside, (Time.get_ticks_usec() - t0) / 1000.0 / RUN_TICKS, sched.street.crowd.usec_spent / 1000.0 / RUN_TICKS]
	print("30 people put on one sidewalk spot, then 1 real minute: overlapping pairs on screen per moment (after 2 s): without the rule %.2f, with it %.2f; positions inside a building with it %d; sim %.2f vs %.2f ms per tick, of it the crowd rule itself %.3f ms" % [
		result[false][0], result[true][0], result[true][1], result[false][2], result[true][2], result[true][3]])
	SimNav.uninstall()
	var ok := _check(result[false][0] > 0.3, "without the rule the clump stays overlapped (the test means something)")
	ok = _check(result[true][0] <= result[false][0] * 0.25, "the crowd rule removes at least three quarters of the overlap") and ok
	ok = _check(result[true][1] == 0, "nobody is pushed into a building") and ok
	return _check(result[true][3] < 0.2, "the crowd rule itself costs under 0.2 ms per tick (1% of a frame; measures 0.13-0.17 run to run)") and ok

## The spot with the most people outdoors within 30 m.
func _busiest(sched: NPCScheduleSystem) -> Vector2:
	var best := Vector2.ZERO
	var most := -1
	for a in sched.street.outside:
		var n := 0
		for b in sched.street.outside:
			n += int(a.position.distance_squared_to(b.position) < 900.0)
		if n > most:
			most = n
			best = a.position
	print("player placed where %d people are within 30 m" % most)
	return best

static func _pairs_closer(people: Array, d: float) -> int:
	var n := 0
	for a in people.size():
		for b in range(a + 1, people.size()):
			n += int(people[a].position.distance_squared_to(people[b].position) < d * d)
	return n

func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("CROWD_VERIFY: FAIL - ", what)
	return ok
