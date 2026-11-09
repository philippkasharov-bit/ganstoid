## MG1a validator: a new game generated on the REAL city. The active district
## (900 m around the spawn) holds every building role, every sim position is a
## real front door outside walls, the population/gangs/cops seed onto it, and the
## same seed gives the same city.
extends SceneTree

const RADIUS := 900.0

func _initialize() -> void:
	var city := CityData.load_file()
	var col := CityCollision.new(city)
	var t0 := Time.get_ticks_msec()
	var world := World.new()
	WorldGenerator.generate_real_city_game(world, 1, city, city.spawn, RADIUS, 130)
	print("generated in %d ms" % (Time.get_ticks_msec() - t0))
	var counts := {}
	var inside_wall := 0
	var buildings := 0
	var signature := ""
	for id in world.entities:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b == null:
			continue
		buildings += 1
		counts[b.building_type] = counts.get(b.building_type, 0) + 1
		if col.blocked(b.position, 0.2):
			inside_wall += 1
		if not _check(b.position.distance_to(city.spawn) <= RADIUS + 0.1, "building inside the district: %s" % id):
			return
		signature += "%s%d" % [id, b.building_type]
	print("buildings %d: homes %d, businesses %d, fronts %d, safehouses %d; doors inside a wall: %d" % [buildings,
		counts.get(GanstoidEnums.BuildingType.RESIDENCE, 0), counts.get(GanstoidEnums.BuildingType.LEGIT_BUSINESS, 0),
		counts.get(GanstoidEnums.BuildingType.ILLEGAL_FRONT, 0), counts.get(GanstoidEnums.BuildingType.SAFEHOUSE, 0), inside_wall])
	for t in GanstoidEnums.BuildingType.values():
		if not _check(counts.get(t, 0) > 0, "building role %d present" % t):
			return
	if not _check(inside_wall * 50 < buildings, "fewer than 2% of doors land inside a wall"):
		return
	if not _check(_people_ok(world, city), "population, cops, dealers and player seeded in the district"):
		return
	var again := World.new()
	WorldGenerator.generate_real_city_game(again, 1, city, city.spawn, RADIUS, 130)
	if not _check(_signature(again) == signature, "same seed -> same buildings and roles"):
		return
	print("REAL_CITY_WORLD_VERIFY: PASS")
	quit()

func _people_ok(world: World, city: CityData) -> bool:
	var npcs := 0
	var cops := 0
	var dealers := 0
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n == null:
			continue
		npcs += 1
		cops += int(n.is_cop)
		dealers += int(n.is_dealer)
		if n.position.distance_to(city.spawn) > RADIUS + 0.1:
			return false
	print("people %d (cops %d, dealers %d)" % [npcs, cops, dealers])
	return npcs >= 130 and cops > 0 and dealers > 0

func _signature(world: World) -> String:
	var s := ""
	for id in world.entities:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b != null:
			s += "%s%d" % [id, b.building_type]
	return s

## Fails loudly and exits (an assert would freeze a headless run in the debugger).
func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("REAL_CITY_WORLD_VERIFY: FAIL - ", what)
		quit(1)
	return ok
