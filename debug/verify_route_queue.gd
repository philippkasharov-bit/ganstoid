## BUG-12 validator: walkers waiting for a route helper are served first come,
## first served. Ten "greedy" walkers ask for a new long route every time they
## get one, and are always asked first (as the sim asks in the same order every
## tick). A quiet walker asked last must still get its route soon. Before the
## queue the greedy ones took every free helper and the last walker never got one.
extends SceneTree

const GREEDY := 10
const WAIT_LIMIT_TICKS := 600   # 10 s at 60 ticks/s; it took forever before

func _initialize() -> void:
	var city := CityData.load_file()
	var nav := SimNav.install(city, city.spawn, TestWorlds.DISTRICT_RADIUS)
	await TestWorlds.wait_nav(self, [nav])
	var goals: Array[Vector2] = []
	for i in 24:
		goals.append(nav.snap(city.spawn + Vector2.from_angle(i * TAU / 24.0) * 300.0, "public"))
	var pos := {}
	var goal := {}
	for i in GREEDY + 1:
		var id := StringName("walker_%d" % i)
		pos[id] = nav.snap(city.spawn + Vector2.from_angle(i * 0.7) * 40.0, "public")
		goal[id] = goals[(i * 7) % goals.size()]
	var last := StringName("walker_%d" % GREEDY)
	var served_at := -1
	var greedy_plans := 0
	for tick in 4000:
		nav.new_tick(tick)
		for i in GREEDY + 1:
			var id := StringName("walker_%d" % i)
			var p: Vector2 = nav.step(id, pos[id], goal[id], 1.5, 1.0 / 60.0, "public")
			var got: bool = nav._plans.has(id)
			if got and i < GREEDY:   # greedy: the moment it has a route, it wants another one
				greedy_plans += 1
				nav.forget(id)
				goal[id] = goals[(tick + i * 5) % goals.size()]
			elif got and id == last and served_at < 0:
				served_at = tick
		if served_at >= 0:
			break
		await process_frame   # the helpers work on other threads
	print("greedy walkers got %d routes; the last walker got its route at tick %d (limit %d)" % [greedy_plans, served_at, WAIT_LIMIT_TICKS])
	nav.finish_async()
	SimNav.uninstall()
	var ok := served_at >= 0 and served_at <= WAIT_LIMIT_TICKS and greedy_plans > 0
	print("ROUTE_QUEUE_VERIFY: PASS" if ok else "ROUTE_QUEUE_VERIFY: FAIL - the last walker waited too long")
	quit(0 if ok else 1)
