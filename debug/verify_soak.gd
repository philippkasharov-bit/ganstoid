## QA3: the long run. The real city on the real clock, nobody at the keys, for
## SOAK_HOURS game hours (default 2: a quick guard in the suite; 72 = three
## days, the full soak, about 25 min). Every 10 game minutes it checks rules
## nobody wrote a check for:
##   - nobody's position is NaN/infinite or off the map (people and cars)
##   - nobody outdoors within sight of the player (NPCStreet.ABSTRACT_M) stands deep
##     inside a building's walls (farther out, walkers go straight on purpose)
##   - nobody holds negative cash; health stays 0..1
##   - civilians on the street don't freeze in place for hours
##   - the world doesn't swell (entity count) or slow down as days pass
## Prints a line per game hour and the worst cases it saw, with ids and places.
## SOAK_HOURS, SOAK_POP (default 1500; the game has 6000), SOAK_SEED (default 7).
extends SceneTree

const CHECK_EVERY_MIN := 10.0
const FROZEN_HOURS := 2.0          # outdoors and not moved 0.5 m for this long = frozen
const FROZEN_SHARE_MAX := 0.01     # of civilians on the street
const DEEP_WALL_M := 1.5           # inside a footprint, this far from every wall: not a doorway
const SLOWDOWN_MAX := 1.6          # an hour's average tick vs the same hour on day 1
const GROWTH_MAX := 0.10           # entities may grow 10% over the run (bodies, cars), no more

var _city: CityData
var _col: CityCollision
var _last_pos := {}    # id -> Vector2
var _still_since := {} # id -> tick it last moved
var _problems := {}    # rule -> {count, example}
var _hour_ms := {}     # hour of day -> first-day average ms/tick

func _initialize() -> void:
	var hours := float(OS.get_environment("SOAK_HOURS")) if OS.has_environment("SOAK_HOURS") else 2.0
	var pop := int(OS.get_environment("SOAK_POP")) if OS.has_environment("SOAK_POP") else 1500
	var seed := int(OS.get_environment("SOAK_SEED")) if OS.has_environment("SOAK_SEED") else 7
	var saved := SimClock.day_ticks
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	_city = CityData.load_file()
	var world := World.new()
	SystemRegistry.register_all(world)
	TrafficSystem.roads = _city.roads
	TrafficSystem.junctions = Junctions.load_file()
	DriveSystem.graph = RoadGraph.build(_city.roads)
	WorldGenerator.generate_real_city_game(world, seed, _city, _city.spawn, 6500.0, pop)
	GameRules.install(world, 1, 1)
	SimNav.install(_city, _city.spawn, TestWorlds.DISTRICT_RADIUS)
	await TestWorlds.wait_nav(self, [SimNav.active])
	_col = SimNav.active.collision
	world.tick = SimClock.hours(7.0)
	(world.find_system(NPCScheduleSystem) as NPCScheduleSystem).settle_all(world.tick)
	var start_entities := world.entities.size()
	var start_mem := OS.get_static_memory_usage()
	print("soak: %.0f game hours, %d people, seed %d, %d entities" % [hours, pop, seed, start_entities])
	var per_check := int(SimClock.hours(CHECK_EVERY_MIN / 60.0))
	var per_hour := int(SimClock.hours(1.0))
	var end_tick := world.tick + int(SimClock.hours(hours))
	var hour_usec := 0
	var hour_ticks := 0
	var hour_worst := 0
	var ok := true
	while world.tick < end_tick:
		var t := Time.get_ticks_usec()
		world.step(1.0 / SimClock.TICKS_PER_SECOND)
		var used := Time.get_ticks_usec() - t
		hour_usec += used
		hour_worst = maxi(hour_worst, used)
		hour_ticks += 1
		if world.tick % per_check == 0:
			_watch(world)
		if world.tick % per_hour == 0:
			var day := SimClock.day_number(world.tick)
			var hod := int(SimClock.day_fraction(world.tick) * 24.0 + 0.5) % 24
			var avg := hour_usec / 1000.0 / hour_ticks
			var slow := ""
			if _hour_ms.has(hod):
				if avg > _hour_ms[hod] * SLOWDOWN_MAX and avg > 0.5:
					_flag("slowdown", "%02d:00 on day %d: %.2f ms/tick vs %.2f on day 1" % [hod, day, avg, _hour_ms[hod]])
					slow = "  SLOWER"
			else:
				_hour_ms[hod] = avg
			print("day %d %02d:00  %.2f ms/tick avg, worst %.1f ms | entities %d | %d MB | problems so far %d%s" % [
				day, hod, avg, hour_worst / 1000.0, world.entities.size(), OS.get_static_memory_usage() / 1048576, _total(), slow])
			hour_usec = 0
			hour_ticks = 0
			hour_worst = 0
			await process_frame   # let route-planning threads hand their work back
	var growth := float(world.entities.size() - start_entities) / start_entities
	if growth > GROWTH_MAX:
		_flag("world swells", "%d -> %d entities (+%.0f%%)" % [start_entities, world.entities.size(), growth * 100.0])
	print("memory %d -> %d MB" % [start_mem / 1048576, OS.get_static_memory_usage() / 1048576])
	SimNav.uninstall()
	SimClock.day_ticks = saved
	print("--- what the run found ---")
	for rule in _problems:
		print("%-14s %5d   e.g. %s" % [rule, _problems[rule]["count"], _problems[rule]["example"]])
	ok = _problems.is_empty()
	if ok:
		print("nothing")
		print("SOAK_VERIFY: PASS")
	else:
		print("SOAK_VERIFY: FAIL - %s" % ", ".join(_problems.keys()))
	quit(0 if ok else 1)

func _watch(world: World) -> void:
	var size := _city.size_m
	var street := 0
	var frozen := 0
	var frozen_eg := ""
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var npc: NPCData = e.get_component(ComponentNames.NPC)
		var p := npc.position
		if not (is_finite(p.x) and is_finite(p.y)):
			_flag("bad position", "%s at %s" % [npc.id, p])
			continue
		if p.x < -50.0 or p.y < -50.0 or p.x > size + 50.0 or p.y > size + 50.0:
			_flag("off the map", "%s at %s" % [npc.id, p])
		if npc.cash < 0:
			_flag("negative cash", "%s has $%d" % [npc.id, npc.cash])
		if npc.health < 0.0 or npc.health > 1.0 or not is_finite(npc.health):
			_flag("bad health", "%s health %s" % [npc.id, npc.health])
		if npc.indoors or npc.is_down or e.has_component(ComponentNames.PLAYER_STATE):
			_last_pos.erase(npc.id)
			continue
		var b := _col.building_at(p) if p.distance_to(me.position) < NPCStreet.ABSTRACT_M - 100.0 else {}   # a margin: walkers coming in from the straight-line zone
		if not b.is_empty() and _wall_distance(p, b["poly"]) > DEEP_WALL_M:
			_flag("inside walls", "%s outdoors at %.1f, %.1f (%.0f m from you), %.1f m inside %s (%s)" % [npc.id, p.x, p.y, p.distance_to(me.position), _wall_distance(p, b["poly"]), b["id"], b.get("kind", "?")])
		if npc.is_cop or npc.is_crew or npc.is_dealer or npc.post_position != Vector2.ZERO:
			continue
		street += 1
		var last: Vector2 = _last_pos.get(npc.id, Vector2.INF)
		if last == Vector2.INF or last.distance_to(p) > 0.5:
			_last_pos[npc.id] = p
			_still_since[npc.id] = world.tick
		elif world.tick - int(_still_since[npc.id]) > SimClock.hours(FROZEN_HOURS):
			frozen += 1
			if frozen_eg == "":
				frozen_eg = "%s still at %.1f, %.1f for %.1f h (home %s, work %s)" % [npc.id, p.x, p.y,
					float(world.tick - int(_still_since[npc.id])) / SimClock.hours(1.0), npc.home_building_id, npc.work_building_id]
	if street > 0 and frozen > maxi(1, int(street * FROZEN_SHARE_MAX)):
		_flag("frozen", "%d of %d on the street; %s" % [frozen, street, frozen_eg])
	for e in world.get_entities_with_component(ComponentNames.VEHICLE).values():
		var car: VehicleData = e.get_component(ComponentNames.VEHICLE)
		var q := car.position
		if not (is_finite(q.x) and is_finite(q.y)) or q.x < -50.0 or q.y < -50.0 or q.x > size + 50.0 or q.y > size + 50.0:
			_flag("car off the map", "%s at %s" % [car.id, q])
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var bd: BuildingData = e.get_component(ComponentNames.BUILDING)
		if bd.cash_on_hand < 0:
			_flag("negative cash", "building %s has $%d" % [bd.id, bd.cash_on_hand])

static func _wall_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, c)))
	return best

func _flag(rule: String, example: String) -> void:
	if not _problems.has(rule):
		_problems[rule] = {"count": 0, "example": example}
		print("PROBLEM %s: %s" % [rule, example])
	_problems[rule]["count"] += 1

func _total() -> int:
	var n := 0
	for rule in _problems:
		n += _problems[rule]["count"]
	return n
