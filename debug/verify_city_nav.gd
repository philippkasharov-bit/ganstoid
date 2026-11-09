## C3 part 2 validator: the walkable network covers the city and paths never go
## through buildings. Streams the tiles around Boyle Heights + Downtown edge and
## runs 80 seeded random trips between street points inside that area.
extends SceneTree

func _initialize() -> void:
	var city := CityData.load_file()
	var col := CityCollision.new(city)
	var t0 := Time.get_ticks_msec()
	var centre := Vector2(4300, 3200)
	var nav := CityNav.new(centre, 700.0)
	await TestWorlds.wait_nav(self, [nav])
	print("nav loaded in %d ms" % (Time.get_ticks_msec() - t0))
	assert(nav.tile_count() > 100 and nav.loaded_count() > 0, "nav tiles found and streamed")
	print("tiles: %d total, %d loaded" % [nav.tile_count(), nav.loaded_count()])
	var pts: Array[Vector2] = []
	for road in city.roads_of("res"):
		for q in road["pts"]:
			if q.distance_to(centre) < 600.0 and not col.blocked(q, 0.5):
				pts.append(q)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ok := 0
	var bad_steps := 0
	var detour := 0.0
	for i in 80:
		var a := pts[rng.randi() % pts.size()]
		var b := pts[rng.randi() % pts.size()]
		var p := nav.path(a, b)
		if p.size() < 2 or p[p.size() - 1].distance_to(b) > 6.0:
			continue
		ok += 1
		var length := 0.0
		for k in p.size() - 1:
			length += p[k].distance_to(p[k + 1])
			for t in [0.25, 0.5, 0.75]:
				if col.blocked(p[k].lerp(p[k + 1], t), 0.0):
					bad_steps += 1
		detour += length / maxf(a.distance_to(b), 1.0)
	print("80 trips in %d ms" % (Time.get_ticks_msec() - t0))
	print("trips found: %d/80, avg detour x%.2f, path steps through a building: %d" % [ok, detour / maxf(ok, 1), bad_steps])
	assert(ok >= 72, "at least 90%% of random trips are walkable")
	assert(bad_steps == 0, "paths never cross a building")
	nav.release()
	print("CITY_NAV_VERIFY: PASS")
	quit()
