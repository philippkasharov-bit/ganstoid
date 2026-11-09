## C3d validator: the civilian (public) navmesh. Random trips between street points
## must be walkable on public ground alone, and no path step may touch private
## ground (yards, lots, gaps) or a building. Also reports how much longer civilian
## routes are than shortcut routes on the full navmesh.
extends SceneTree

const CENTRE := Vector2(4300, 3200)
const TRIPS := 80

func _initialize() -> void:
	var city := CityData.load_file()
	var col := CityCollision.new(city)
	var t0 := Time.get_ticks_msec()
	var pub := CityNav.new(CENTRE, 700.0, "public")
	var full := CityNav.new(CENTRE, 700.0, "full")
	print("public tiles: %d total, %d loaded in %d ms" % [pub.tile_count(), pub.loaded_count(), Time.get_ticks_msec() - t0])
	if not _check(pub.tile_count() > 100 and pub.loaded_count() > 0, "public nav tiles found and streamed"):
		return
	var zones := _zones_near(city, Rect2(CENTRE - Vector2(800, 800), Vector2(1600, 1600)))
	var pts := _street_points(city, col, pub)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok := 0
	var private_steps := 0
	var building_steps := 0
	var ratio := 0.0
	for i in TRIPS:
		var a: Vector2 = pts[rng.randi() % pts.size()]
		var b: Vector2 = pts[rng.randi() % pts.size()]
		var p := pub.path(a, b)
		if p.size() < 2 or p[p.size() - 1].distance_to(b) > 6.0:
			continue
		ok += 1
		for k in p.size() - 1:
			for t in [0.0, 0.5]:
				var q := p[k].lerp(p[k + 1], t)
				if col.blocked(q, 0.0):
					building_steps += 1
				elif not _on_public(q, zones):
					private_steps += 1
		ratio += _length(p) / maxf(_length(full.path(a, b)), 1.0)
	print("civilian trips found: %d/%d, path steps on private ground: %d, through buildings: %d" % [ok, TRIPS, private_steps, building_steps])
	print("civilian route vs shortcut route: x%.2f longer on average" % (ratio / maxf(ok, 1)))
	if not _check(ok >= int(TRIPS * 0.9), "at least 90% of civilian trips are walkable on public ground"):
		return
	if not _check(private_steps == 0 and building_steps == 0, "civilians never trespass or clip buildings"):
		return
	pub.release()
	full.release()
	print("CITY_NAV_PUBLIC_VERIFY: PASS")
	quit()

## Fails loudly and exits (an assert would freeze a headless run in the debugger).
func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("CITY_NAV_PUBLIC_VERIFY: FAIL - ", what)
		quit(1)
	return ok

## Street points that sit on the public navmesh (start/end of civilian trips).
func _street_points(city: CityData, col: CityCollision, pub: CityNav) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for road in city.roads_of("res"):
		for q in road["pts"]:
			if q.distance_to(CENTRE) < 600.0:
				var s := pub.closest(q)
				if s.distance_to(q) < 8.0 and not col.blocked(s, 0.3):
					out.append(s)
	return out

func _zones_near(city: CityData, area: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z in city.public_zones:
		var r := _bounds(z["outer"])
		if r.intersects(area):
			var holes: Array = []
			for h in z["holes"]:
				var hb := _bounds(h)
				if hb.intersects(area):
					holes.append([hb, h])
			out.append({"bb": r, "outer": z["outer"], "holes": holes})
	return out

## On public ground = inside a zone and outside its holes. 0.5 m tolerance: path steps hop the
## 0.8 m seam where two public regions meet (each is shrunk by the 0.4 m agent radius).
func _on_public(p: Vector2, zones: Array[Dictionary]) -> bool:
	for d in [Vector2.ZERO, Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
		var q: Vector2 = p + d
		for z in zones:
			if not z["bb"].has_point(q) or not Geometry2D.is_point_in_polygon(q, z["outer"]):
				continue
			var in_hole := false
			for h in z["holes"]:
				if h[0].has_point(q) and Geometry2D.is_point_in_polygon(q, h[1]):
					in_hole = true
					break
			if not in_hole:
				return true
	return false

func _length(p: PackedVector2Array) -> float:
	var total := 0.0
	for k in p.size() - 1:
		total += p[k].distance_to(p[k + 1])
	return total

func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
