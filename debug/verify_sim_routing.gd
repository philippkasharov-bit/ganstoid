## MG1b validator: the sim's movers walk the real city. With SimNav installed for
## the district, civilians, dealers and cops move along navmesh routes: over a
## stretch of sim time nobody is ever inside a building, people actually move at
## walking pace (not the old 60 m/s), and the player slides along walls.
extends SceneTree

const TICKS := 3000          # 50 real seconds
const SAMPLE_EVERY := 30

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world)
	var city := TestWorlds.city()
	var t0 := Time.get_ticks_msec()
	SimNav.install(city, city.spawn, TestWorlds.DISTRICT_RADIUS)
	await TestWorlds.wait_nav(self, [SimNav.active])
	print("navmeshes loaded in %d ms" % (Time.get_ticks_msec() - t0))
	var col := CityCollision.new(city)
	var movers := _movers(world)
	var start := {}
	for id in movers:
		start[id] = movers[id].position
	var inside := 0
	var fastest := 0.0
	var last := start.duplicate()
	t0 = Time.get_ticks_msec()
	for t in TICKS:
		world.step(1.0 / SimClock.TICKS_PER_SECOND)
		if t % SAMPLE_EVERY == 0:
			for id in movers:
				var p: Vector2 = movers[id].position
				inside += int(col.blocked(p, 0.0))
				fastest = maxf(fastest, p.distance_to(last[id]) / (float(SAMPLE_EVERY) / SimClock.TICKS_PER_SECOND))
				last[id] = p
	var ms_per_tick := float(Time.get_ticks_msec() - t0) / TICKS
	var moved := 0
	for id in movers:
		moved += int(movers[id].position.distance_to(start[id]) > 5.0)
	print("movers %d, moved >5 m: %d, samples inside a building: %d, fastest %.1f m/s, %.2f ms per tick" % [movers.size(), moved, inside, fastest, ms_per_tick])
	if not _check(inside == 0, "nobody walks inside a building"):
		return
	if not _check(moved * 4 >= movers.size(), "at least a quarter of people moved somewhere"):
		return
	if not _check(fastest <= SimUnits.SPRINT + 0.5, "nobody moves faster than a sprint"):
		return
	if not _check(_player_slides(city, col), "the player slides along walls instead of walking through them"):
		return
	SimNav.uninstall()
	print("SIM_ROUTING_VERIFY: PASS")
	quit()

## Push the player straight at the nearest building for 10 s: they must never end up inside it.
func _player_slides(city: CityData, col: CityCollision) -> bool:
	var b: Dictionary = city.buildings[0]
	var best := INF
	for c in city.buildings:
		var d: float = c["door"].distance_to(city.spawn)
		if d < best:
			best = d
			b = c
	var p: Vector2 = b["door"]
	var into: Vector2 = (b["poly"][0] - p).normalized()
	for i in 600:
		p = SimNav.active.slide(p, into * SimUnits.WALK / SimClock.TICKS_PER_SECOND)
		if col.blocked(p, 0.0):
			return false
	return true

func _movers(world: World) -> Dictionary:
	var out := {}
	for id in world.entities:
		var e: Entity = world.entities[id]
		if e.has_component(ComponentNames.NPC) and not e.has_component(ComponentNames.PLAYER_STATE):
			out[id] = e.get_component(ComponentNames.NPC)
	return out

## Fails loudly and exits (an assert would freeze a headless run in the debugger).
func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("SIM_ROUTING_VERIFY: FAIL - ", what)
		quit(1)
	return ok
