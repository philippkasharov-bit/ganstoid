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
	await TestWorlds.wait_nav(self, [pub, full])
	print("public tiles: %d total, %d loaded in %d ms" % [pub.tile_count(), pub.loaded_count(), Time.get_ticks_msec() - t0])
	if not _check(pub.tile_count() > 100 and pub.loaded_count() > 0, "public nav tiles found and streamed"):
		return
	var zones := _zones_near(city, Rect2(CENTRE - Vector2(800, 800), Vector2(1600, 1600)))
	zones.append_array(_shop_lots_near(Rect2(CENTRE - Vector2(800, 800), Vector2(1600, 1600))))   # MR6: public while open
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
					print("  through a building at ", q, " step ", p[k], " -> ", p[k + 1])
				elif not _on_public(q, zones):
					private_steps += 1
					print("  private ground at ", q, " step ", p[k], " -> ", p[k + 1])
		ratio += _length(p) / maxf(_length(full.path(a, b)), 1.0)
	print("civilian trips found: %d/%d, path steps on private ground: %d, through buildings: %d" % [ok, TRIPS, private_steps, building_steps])
	print("civilian route vs shortcut route: x%.2f longer on average" % (ratio / maxf(ok, 1)))
	if not _check(ok >= int(TRIPS * 0.9), "at least 90% of civilian trips are walkable on public ground"):
		return
	if not _check(private_steps == 0 and building_steps == 0, "civilians never trespass or clip buildings"):
		return
	if not _check(await _civilians_avoid_alleys(pub, pts, zones), "civilians use alleys less than dark-route NPCs"):
		return
	if not _check(await _shop_lots_open_by_day(pts, zones), "civilians cross shop lots by day more than at night"):
		return
	if not _check(_civilians_keep_to_paving(city, pub, pts), "civilians walk the paving, not the parkway grass"):
		return
	if not _check(await _district_is_one_piece(city), "civilians can reach the whole spawn district on public ground"):
		return
	pub.release()
	full.release()
	print("CITY_NAV_PUBLIC_VERIFY: PASS")
	quit()

## Same trips with alley cost 3 (civilian, day) vs 1 (dark-route): civilians must walk
## a smaller share of their route in alleys.
func _civilians_avoid_alleys(pub: CityNav, pts: Array[Vector2], zones: Array[Dictionary]) -> bool:
	var alleys: Array[Dictionary] = zones.filter(func(z: Dictionary) -> bool: return z["kind"] == "alley")
	var share := {}
	for cost in [3.0, 1.0]:
		var nav := CityNav.new(CENTRE, 700.0, "public", cost)   # cost fixed before the tiles sync
		await TestWorlds.wait_nav(self, [nav])
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var in_alley := 0.0
		var total := 0.0
		for i in TRIPS:
			var p := nav.path(pts[rng.randi() % pts.size()], pts[rng.randi() % pts.size()])
			for k in p.size() - 1:
				var seg := p[k].distance_to(p[k + 1])
				total += seg
				if _on_public(p[k].lerp(p[k + 1], 0.5), alleys):
					in_alley += seg
		share[cost] = in_alley / maxf(total, 1.0)
		nav.release()
	print("share of route in alleys: civilian %.1f%%, dark-route %.1f%%" % [share[3.0] * 100, share[1.0] * 100])
	return share[3.0] < share[1.0]

## MR6: same trips with shop lots open (cost 1, 07:00-22:00) and closed (cost 20):
## by day a bigger share of the route runs across lots.
func _shop_lots_open_by_day(pts: Array[Vector2], zones: Array[Dictionary]) -> bool:
	var lots: Array[Dictionary] = zones.filter(func(z: Dictionary) -> bool: return z["kind"] == "lot")
	var share := {}
	for cost in [1.0, SimNav.CLOSED_LOT_COST]:
		var nav := CityNav.new(CENTRE, 700.0, "public", 3.0)
		nav.lot_cost = cost
		await TestWorlds.wait_nav(self, [nav])
		var rng := RandomNumberGenerator.new()
		rng.seed = 13
		var on_lot := 0.0
		var total := 0.0
		for i in TRIPS:
			var p := nav.path(pts[rng.randi() % pts.size()], pts[rng.randi() % pts.size()])
			for k in p.size() - 1:
				var seg := p[k].distance_to(p[k + 1])
				total += seg
				if _on_public(p[k].lerp(p[k + 1], 0.5), lots):
					on_lot += seg
		share[cost] = on_lot / maxf(total, 1.0)
		nav.release()
	print("share of route across shop lots: open %.1f%%, closed %.1f%%" % [share[1.0] * 100, share[SimNav.CLOSED_LOT_COST] * 100])
	return share[1.0] > share[SimNav.CLOSED_LOT_COST]

## Shop, office, civic and parking lots (the ground baked as the public "lot" layer).
func _shop_lots_near(area: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lot in CityReal.load_files().lots:
		if lot["use"] in ["parking", "commercial", "civic"]:
			var r := _bounds(lot["poly"])
			if r.intersects(area):
				out.append({"kind": "lot", "bb": r, "outer": lot["poly"], "holes": []})
	return out

## MP2b: parkway grass is off the civilian mesh except where the paving beside it
## is broken, so only a small share of any route may run on grass (it was 26%
## when grass and paving were one surface).
func _civilians_keep_to_paving(city: CityData, pub: CityNav, pts: Array[Vector2]) -> bool:
	var grid := _parkway_grid(city)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var on_grass := 0.0
	var total := 0.0
	for i in TRIPS:
		var p := pub.path(pts[rng.randi() % pts.size()], pts[rng.randi() % pts.size()])
		for k in p.size() - 1:
			var steps := maxi(1, int(p[k].distance_to(p[k + 1]) / 2.0))
			for j in steps:
				total += 1.0
				if _on_parkway(p[k].lerp(p[k + 1], (j + 0.5) / steps), grid):
					on_grass += 1.0
	var share := on_grass / maxf(total, 1.0)
	print("share of civilian route on parkway grass: %.1f%%" % (share * 100))
	return total > 0.0 and share < MAX_GRASS_SHARE

## The player's district must be one piece for civilians: from one sidewalk point
## nearly every other sidewalk point within 900 m is reachable on public ground.
## (Before MP2b the freeway cut it in two: 514 of 676 points.)
func _district_is_one_piece(city: CityData) -> bool:
	var nav := CityNav.new(city.spawn, 1100.0, "public", 3.0)
	await TestWorlds.wait_nav(self, [nav])
	var pts: Array[Vector2] = []
	for road in city.roads:
		if road.get("side", 0.0) > 0.0:
			for q in road["pts"]:
				if q.distance_to(city.spawn) < 900.0:
					pts.append(nav.closest(q + Vector2(road["w"] * 0.5 + road["side"] - 0.8, 0)))
	var best := 0
	for seed_i in [0, pts.size() / 3, pts.size() * 2 / 3]:   # three starts, in case one sits on an island
		var reached := 0
		for q in pts:
			var p := nav.path(pts[seed_i], q)
			if pts[seed_i].distance_to(q) < 0.5 or (p.size() >= 2 and p[p.size() - 1].distance_to(q) < 1.0):
				reached += 1
		best = maxi(best, reached)
	nav.release()
	print("spawn district: %d of %d sidewalk points reachable on public ground" % [best, pts.size()])
	return best >= int(pts.size() * ONE_PIECE_SHARE)

const MAX_GRASS_SHARE := 0.12
const ONE_PIECE_SHARE := 0.97
const GRID_CELL := 50.0

## cell -> street segments [a, b, half roadway, parkway width] of streets that have a parkway.
func _parkway_grid(city: CityData) -> Dictionary:
	var grid := {}
	for road in city.roads:
		var park: float = road.get("park", 0.0)
		if park <= 0.0 or road["pts"][0].distance_to(CENTRE) > 1500.0:
			continue
		var pts: PackedVector2Array = road["pts"]
		for i in pts.size() - 1:
			var r := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(float(road["w"]) * 0.5 + park + 1.0)
			for x in range(int(r.position.x / GRID_CELL), int(r.end.x / GRID_CELL) + 1):
				for y in range(int(r.position.y / GRID_CELL), int(r.end.y / GRID_CELL) + 1):
					var key := Vector2i(x, y)
					if not grid.has(key):
						grid[key] = []
					grid[key].append([pts[i], pts[i + 1], float(road["w"]) * 0.5, park])
	return grid

## Between the kerb and the paving of some street (0.2 m inside the strip, to be sure).
func _on_parkway(p: Vector2, grid: Dictionary) -> bool:
	for seg in grid.get(Vector2i(int(p.x / GRID_CELL), int(p.y / GRID_CELL)), []):
		var d := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p)
		if d > seg[2] + 0.2 and d < seg[2] + seg[3] - 0.2:
			return true
	return false

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
			out.append({"kind": z["kind"], "bb": r, "outer": z["outer"], "holes": holes})
	return out

## On public ground = inside a zone and outside its holes. 0.6 m tolerance: path steps hop the
## 0.8 m seam where two public regions meet (each is shrunk by the 0.4 m agent radius), and
## a hop at a slant lands a little further than half of it.
func _on_public(p: Vector2, zones: Array[Dictionary]) -> bool:
	for d in [Vector2.ZERO, Vector2(0.6, 0), Vector2(-0.6, 0), Vector2(0, 0.6), Vector2(0, -0.6)]:
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
