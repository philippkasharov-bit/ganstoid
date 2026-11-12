## City map renderer (C1, MP1, perf pass): draws a CityData (areas, river, rail,
## sidewalks, streets, buildings, elevated freeways) in world metres. Render
## layer only: reads the data, never changes it.
## Performance: the map is split into layers x 12x12 tiles (~500 m), each its own
## canvas item, so Godot only submits tiles on screen; round road joints are
## drawn only where a road actually bends; fine layers are hidden when zoomed out.
## Day/night switch redraws every tile. Real-ground painters live in CityGround.
class_name CityRenderer
extends Node2D

const DRAW_ORDER: Array[String] = ["trail", "aisle", "drive", "path", "alley", "svc", "hill", "res", "art"]   # under buildings
const OVER_BUILDINGS: Array[String] = ["ramp", "fwy"]   # elevated: drawn over everything

## Every road tier the map draws (checked against the palettes by verify_render_palette).
static func TIERS_DRAWN() -> Array:
	return DRAW_ORDER + OVER_BUILDINGS
## Fallback widths; MP1 roads carry their real roadway width ("w") and sidewalk+parkway ("side").
const WIDTH := {"fwy": 26.0, "ramp": 6.0, "art": 14.0, "res": 6.0, "alley": 3.0, "path": 2.5, "svc": 7.0, "hill": 5.0, "trail": 2.5, "aisle": 7.3, "drive": 3.7}
const CASING := {"fwy": 3.0, "ramp": 2.0}   # elevated roads get a shadowed edge; streets use the kerb instead
const BUILDING_DAY := {"house": Color("d9c7a8"), "apartments": Color("cdb48f"), "commercial": Color("c9b9a4"), "industrial": Color("b4b8bc"),
	"garage": Color("d8d2c4"), "civic": Color("c7a98f"), "building": Color("cfc3ad")}
const BUILDING_NIGHT := {"house": Color("232733"), "apartments": Color("2a2c38"), "commercial": Color("2b2a33"), "industrial": Color("1e2029"),
	"garage": Color("1c1e26"), "civic": Color("2e2a30"), "building": Color("252833")}
const DAY := {
	"bg": Color("f1ebde"), "hills": Color("e1e7d1"), "mountains": Color("c3cfb5"), "park": Color("c7dbb3"),
	"airfield": Color("e4e0d4"), "foothill": Color("ede4d2"), "industrial": Color("dcd8e2"), "downtown": Color("ddd0b6"), "commercial": Color("e6d9c0"),
	"river": Color("c4cfd6"), "rail": Color("7d7468"),
	"fwy": Color("807f7a"), "fwy_c": Color("5b5a56"), "ramp": Color("8a8984"), "ramp_c": Color("6a6964"), "art": Color("8e8d89"), "art_c": Color("74726d"),
	"res": Color("a09d96"), "alley": Color("b0aca4"), "path": Color("cfcbc1"), "svc": Color("b5b2ab"), "hill": Color("a89d82"), "trail": Color("9b8357"),
	"aisle": Color("a6a49e"), "drive": Color("d3cfc5"),
	"walk": Color("d6d3cb"), "kerb": Color("b3aea3"),
	"parkway": Color("c6cdab"), "well": Color("8d7b5e"), "ramp_f": Color("e5e2d9"),
}
const NIGHT := {
	"bg": Color("151a26"), "hills": Color("0b0f14"), "mountains": Color("080b0f"), "park": Color("0b130d"),
	"airfield": Color("10131c"), "foothill": Color("141824"), "industrial": Color("111420"), "downtown": Color("2a2228"), "commercial": Color("231f26"),
	"river": Color("090c12"), "rail": Color("1d1c22"),
	"fwy": Color("ffc066"), "fwy_c": Color("3b2a14"), "ramp": Color("a7782f"), "ramp_c": Color("2c2414"), "art": Color("f3a443"), "art_c": Color("6b4a1a"),
	"res": Color("3d4054"), "alley": Color("0a0b10"), "path": Color("1f222a"), "svc": Color("2c2f3c"), "hill": Color("262a33"), "trail": Color("1b1a17"),
	"aisle": Color("20232c"), "drive": Color("22252d"),
	"walk": Color("23262f"), "kerb": Color("191b22"),
	"parkway": Color("181d1a"), "well": Color("101110"), "ramp_f": Color("2b2f3a"),
}

const PUBLIC_COLORS := {"sidewalk": Color(0.1, 0.6, 1.0, 0.75), "alley": Color(1.0, 0.55, 0.1, 0.8), "path": Color(0.2, 0.85, 0.4, 0.8), "park": Color(0.3, 0.8, 0.3, 0.45)}

var city: CityData
var night := false:
	set(v):
		night = v
		_redraw_all()
var show_public := false:   # overlay: where civilians may walk (sidewalks, crosswalks, alleys, parks)
	set(v):
		show_public = v
		_redraw_all()
var show_markers := true:
	set(v):
		show_markers = v
		_redraw_all()

const TILES := 12
const JOINT_TURN_DEG := 15.0   # bends sharper than this get a round joint

## Level of detail: a layer is only shown from the zoom at which it is more than a
## smudge. Hiding a layer costs nothing; drawing 60,000 tree wells from orbit does.
const FINE_ZOOM := 4.0   # pixels per metre: kerb ramps, tree wells, fences, lot lines, furniture
const MID_ZOOM := 1.2    # trees, marked crossings

const JOIN_SNAP_M := 0.5   # road ends closer than this are the same point

var real: CityReal          # what is really on the ground (MR2); null = older data only
var _joins := {}
var _nodes: Array[Node2D] = []
var _lod: Array = []        # [node, min zoom] for every layer that has one
var _zoom_seen := -1.0

func _process(_delta: float) -> void:
	if city != null and _nodes.is_empty():
		_build()
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var zoom := cam.zoom.x if cam != null else 1000.0
	if zoom != _zoom_seen:
		_zoom_seen = zoom
		for entry in _lod:
			entry[0].visible = zoom >= entry[1] and (entry[2] <= 0.0 or zoom < entry[2])

func _redraw_all() -> void:
	for n in _nodes:
		n.queue_redraw()

## One node per (layer, tile); node order = draw order (later nodes paint over earlier ones).
func _build() -> void:
	_find_joins()
	if real == null:
		real = CityReal.load_files()
	_add_layer(func(ci: CanvasItem, _r: Rect2) -> void: _draw_base(ci), [Rect2()])
	var tiles := _tile_rects()
	var roads := _bucket(city.roads, tiles, func(r: Dictionary) -> Rect2: return _bounds(r["pts"]).grow(r.get("w", WIDTH[r["tier"]]) * 0.5 + r.get("side", 0.0)))
	var blds := _bucket(city.buildings, tiles, _centre_of_poly)
	var lots := _bucket(real.lots, tiles, _centre_of_poly)
	var surfaces := _bucket(real.surfaces, tiles, _centre_of_poly)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: CityGround.lots(ci, lots[r], night), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: CityGround.surfaces(ci, surfaces[r], night), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: CityGround.lot_lines(ci, lots[r], night), tiles, FINE_ZOOM)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_sidewalks(ci, roads[r]), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_tiers(ci, roads[r], DRAW_ORDER), tiles)
	var drives := _bucket(city.driveways, tiles, _feature_bounds)
	var ramps := _bucket(city.kerb_ramps, tiles, _feature_bounds)
	var wells := _bucket_points(city.tree_wells, tiles)
	var crossings := _bucket(real.crossings, tiles, func(c: Dictionary) -> Rect2: return Rect2(c["pts"][0], Vector2.ZERO))
	var barriers := _bucket(real.barriers, tiles, func(b: Dictionary) -> Rect2: return Rect2(b["pts"][0], Vector2.ZERO))
	var points := _bucket(real.points, tiles, func(p: Dictionary) -> Rect2: return Rect2(p["p"], Vector2.ZERO))
	var trees := _bucket_points(real.trees, tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: StreetPainter.paint(ci, roads[r], night), tiles, MID_ZOOM)   # SL1: lane markings
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_driveways(ci, drives[r]), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: CityGround.crossings(ci, crossings[r], night), tiles, MID_ZOOM)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_band_details(ci, ramps[r], wells[r]), tiles, FINE_ZOOM)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: CityGround.details(ci, barriers[r], points[r], night), tiles, FINE_ZOOM)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_buildings(ci, blds[r]), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_building_details(ci, blds[r]), tiles, MID_ZOOM)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: CityGround.trees(ci, trees[r], night), tiles, MID_ZOOM)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: FreewayPainter.paint(ci, roads[r].filter(func(x: Dictionary) -> bool: return OVER_BUILDINGS.has(x["tier"])), WIDTH, night, false), tiles, 0.0, MID_ZOOM)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: FreewayPainter.paint(ci, roads[r].filter(func(x: Dictionary) -> bool: return OVER_BUILDINGS.has(x["tier"])), WIDTH, night, true), tiles, MID_ZOOM)   # MF1: with lane striping up close
	_add_layer(func(ci: CanvasItem, _r: Rect2) -> void: _draw_overlays(ci), [Rect2()])

func _add_layer(painter: Callable, rects: Array, min_zoom := 0.0, max_zoom := 0.0) -> void:
	for rect in rects:
		var n := Node2D.new()
		n.draw.connect(func() -> void: painter.call(n, rect))
		add_child(n)
		_nodes.append(n)
		if min_zoom > 0.0 or max_zoom > 0.0:
			_lod.append([n, min_zoom, max_zoom])

static func _centre_of_poly(item: Dictionary) -> Rect2:
	return Rect2(_bounds(item["poly"]).get_center(), Vector2.ZERO)

func _tile_rects() -> Array:
	var size := city.size_m / TILES
	var out := []
	for x in TILES:
		for y in TILES:
			out.append(Rect2(x * size, y * size, size, size))
	return out

## rect -> items whose bounds touch it (roads that cross tiles appear in each).
func _bucket(items: Array, tiles: Array, bounds_of: Callable) -> Dictionary:
	var size := city.size_m / TILES
	var out := {}
	for t in tiles:
		out[t] = []
	for it in items:
		var b: Rect2 = bounds_of.call(it)
		for x in range(clampi(int(b.position.x / size), 0, TILES - 1), clampi(int(b.end.x / size), 0, TILES - 1) + 1):
			for y in range(clampi(int(b.position.y / size), 0, TILES - 1), clampi(int(b.end.y / size), 0, TILES - 1) + 1):
				out[tiles[x * TILES + y]].append(it)
	return out

## rect -> the points inside it (tree wells: one point each, no bounds needed).
func _bucket_points(points: PackedVector2Array, tiles: Array) -> Dictionary:
	var size := city.size_m / TILES
	var out := {}
	for t in tiles:
		out[t] = PackedVector2Array()
	for p in points:
		var x := clampi(int(p.x / size), 0, TILES - 1)
		var y := clampi(int(p.y / size), 0, TILES - 1)
		out[tiles[x * TILES + y]].append(p)
	return out

static func _feature_bounds(f: Dictionary) -> Rect2:
	return Rect2(f["c"], Vector2.ZERO).grow(maxf(float(f["w"]), float(f["len"])))

func _pal() -> Dictionary:
	return NIGHT if night else DAY

func _draw_base(ci: CanvasItem) -> void:
	var pal := _pal()
	ci.draw_rect(Rect2(Vector2.ZERO, Vector2(city.size_m, city.size_m)), pal["bg"])
	for area in city.areas:
		var poly: PackedVector2Array = area["poly"]
		if poly.size() > 2 and poly[0] == poly[poly.size() - 1]:
			poly = poly.slice(0, poly.size() - 1)
		if Geometry2D.triangulate_polygon(poly).size() > 0:
			ci.draw_colored_polygon(poly, pal.get(area["kind"], pal["bg"]))
	ci.draw_polyline(city.river, pal["river"].darkened(0.15), 70.0)
	ci.draw_polyline(city.river, pal["river"], 46.0)
	for line in city.rail:
		for i in range(0, line.size() - 1):
			ci.draw_dashed_line(line[i], line[i + 1], pal["rail"], 3.0, 14.0)

## The real LA cross-section each side of a street (MP1 widths, MP2 split), drawn
## outermost band first: concrete paving over the whole side, the parkway strip
## over its inner half where there is one, then the kerb face at the roadway edge.
func _draw_sidewalks(ci: CanvasItem, roads: Array) -> void:
	var pal := _pal()
	for band in ["walk", "parkway", "kerb"]:
		for road in roads:
			var side: float = road.get("side", 0.0)
			if side <= 0.0:
				continue
			match band:
				"walk":
					_thick_line(ci, road, pal["walk"], 2.0 * side)
				"parkway":
					var park: float = road.get("park", 0.0)
					if park > 0.0:
						_thick_line(ci, road, pal["parkway"], 2.0 * park)
				"kerb":
					_thick_line(ci, road, pal["kerb"], 0.6)   # kerb face + gutter joint

## Driveway cuts: concrete across the band and over the kerb.
func _draw_driveways(ci: CanvasItem, drives: Array) -> void:
	var col: Color = _pal()["walk"]
	for d in drives:
		_band_strip(ci, d, col, 0.5)   # 0.5 m into the gutter: the kerb is cut down here

## Kerb ramps at the crosswalk ends and the tree wells MP5 will plant into.
func _draw_band_details(ci: CanvasItem, ramps: Array, wells: PackedVector2Array) -> void:
	var pal := _pal()
	for r in ramps:
		_band_strip(ci, r, pal["ramp_f"], 0.0)
	for p in wells:
		ci.draw_circle(p, city.well_r, pal["well"])

## A strip w metres wide running from `into` metres inside the roadway out across
## the band. Drawn as a wide line: a four-point polygon this small and this far
## from the origin sometimes fails Godot's triangulation.
static func _band_strip(ci: CanvasItem, f: Dictionary, col: Color, into: float) -> void:
	var d: Vector2 = f["dir"]
	ci.draw_line(f["c"] - d * into, f["c"] + d * float(f["len"]), col, float(f["w"]))

## Per tier: all edges first, then all fills, so one road's edge never paints over its neighbour.
func _draw_tiers(ci: CanvasItem, roads: Array, tiers: Array[String]) -> void:
	var pal := _pal()
	for tier in tiers:
		if CASING.has(tier):
			for road in roads:
				if road["tier"] == tier:
					_thick_line(ci, road, pal[tier + "_c"], CASING[tier])
		for road in roads:
			if road["tier"] == tier:
				_thick_line(ci, road, pal[tier], 0.0)

## MP7: buildings with height. Each casts a shadow away from the afternoon
## sun as long as it is tall (3.2 m a storey); taller roofs read a touch
## lighter, towers get rooftop plant; shops and restaurants get a coloured
## awning over the wall their door is on.
const STOREY_M := 3.2
const SHADOW_DIR := Vector2(0.55, 0.42)       # metres of shadow per metre of height
const SHADOW_MAX_M := 45.0
const AWNINGS := [Color("b23a3a"), Color("2f6d8f"), Color("3f7f4f"), Color("c08a2e"), Color("6b4a8f"), Color("d0d0c8")]

## Roofs only (every zoom). Shadows dropped (Phil: not needed).
func _draw_buildings(ci: CanvasItem, blds: Array) -> void:
	var cols: Dictionary = BUILDING_NIGHT if night else BUILDING_DAY
	for b in blds:
		var poly: PackedVector2Array = b["poly"]
		var open_poly := poly.slice(0, poly.size() - 1) if poly[0] == poly[poly.size() - 1] else poly
		if open_poly.size() < 3 or Geometry2D.triangulate_polygon(open_poly).is_empty():
			continue   # a footprint Godot cannot fill (self-touching): skip rather than error
		var levels: int = b.get("levels", 1)
		ci.draw_colored_polygon(open_poly, cols.get(b["kind"], cols["building"]).lightened(minf(0.18, levels * 0.012)))

## Walls, rooftop plant and shop awnings: only up close, where you can see them
## (at city zoom these thousands of lines were most of the cost of zooming).
func _draw_building_details(ci: CanvasItem, blds: Array) -> void:
	var cols: Dictionary = BUILDING_NIGHT if night else BUILDING_DAY
	for b in blds:
		var poly: PackedVector2Array = b["poly"]
		var open_poly := poly.slice(0, poly.size() - 1) if poly[0] == poly[poly.size() - 1] else poly
		if open_poly.size() < 3:
			continue
		var levels: int = b.get("levels", 1)
		var col: Color = cols.get(b["kind"], cols["building"]).lightened(minf(0.18, levels * 0.012))
		ci.draw_polyline(poly, col.darkened(0.3), 0.3)   # wall outline, metres
		if levels >= 6:
			_rooftop(ci, open_poly, col)
		if b["kind"] == "commercial" and b.has("door"):
			_awning(ci, open_poly, b["door"], b["id"])

static func _moved(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out

## Plant on a tall roof: a couple of boxes near the middle.
func _rooftop(ci: CanvasItem, poly: PackedVector2Array, col: Color) -> void:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	if not Geometry2D.is_point_in_polygon(c, poly):
		return
	ci.draw_rect(Rect2(c - Vector2(3, 2), Vector2(6, 4)), col.darkened(0.18))
	ci.draw_rect(Rect2(c + Vector2(4, -1), Vector2(2.5, 2.5)), col.darkened(0.25))

## A shopfront awning along the wall nearest the door.
func _awning(ci: CanvasItem, poly: PackedVector2Array, door: Vector2, id: StringName) -> void:
	var best := 0
	var best_d := INF
	for i in poly.size():
		var d := Geometry2D.get_closest_point_to_segment(door, poly[i], poly[(i + 1) % poly.size()]).distance_to(door)
		if d < best_d:
			best_d = d
			best = i
	var a: Vector2 = poly[best]
	var c: Vector2 = poly[(best + 1) % poly.size()]
	var len := a.distance_to(c)
	if len < 3.0:
		return
	var along := (c - a) / len
	var out := along.orthogonal()
	if (door - a).dot(out) < 0.0:
		out = -out   # outward: toward the street the door faces
	var span := minf(len - 1.0, 12.0)
	var mid := Geometry2D.get_closest_point_to_segment(door, a, c)
	var s0 := mid - along * span * 0.5
	var s1 := mid + along * span * 0.5
	var col: Color = AWNINGS[absi(hash(id)) % AWNINGS.size()]
	ci.draw_colored_polygon(PackedVector2Array([s0, s1, s1 + out * 1.4, s0 + out * 1.4]), col.darkened(0.45) if night else col)

## A wide polyline with round joints at real bends, and at an end only where
## another road carries on from that point. The joint there is as wide as the
## narrower of the two, so a boulevard meeting a side street no longer bulges
## past it; a road that simply stops (dead end, ramp merging into a freeway,
## street running into the side of another) ends square.
## `extra` is what this pass adds to the roadway width (sidewalk band, kerb, casing).
func _thick_line(ci: CanvasItem, road: Dictionary, col: Color, extra: float) -> void:
	var pts: PackedVector2Array = road["pts"]
	var w: float = road.get("w", WIDTH[road["tier"]])
	ci.draw_polyline(pts, col, w + extra)
	var n := pts.size()
	for i in range(1, n - 1):
		if absf((pts[i] - pts[i - 1]).angle_to(pts[i + 1] - pts[i])) > deg_to_rad(JOINT_TURN_DEG):
			ci.draw_circle(pts[i], (w + extra) * 0.5, col)
	var joins: Vector2 = _joins.get(road["id"], Vector2.ZERO)   # width of the road met at the start / at the end
	if joins.x > 0.0:
		ci.draw_circle(pts[0], (minf(w, joins.x) + extra) * 0.5, col)
	if joins.y > 0.0:
		ci.draw_circle(pts[n - 1], (minf(w, joins.y) + extra) * 0.5, col)

## road id -> (widest other road sharing its first point, widest sharing its last point); 0 = none.
## Only roads drawn in the same pass group join: a street does not join the freeway above it.
func _find_joins() -> void:
	var at := {}   # [group, snapped point] -> Array of [id, w]
	for road in city.roads:
		var group := 1 if OVER_BUILDINGS.has(road["tier"]) else 0
		var w: float = road.get("w", WIDTH[road["tier"]])
		for p in [road["pts"][0], road["pts"][road["pts"].size() - 1]]:
			var key := [group, Vector2i((p / JOIN_SNAP_M).round())]
			if not at.has(key):
				at[key] = []
			at[key].append([road["id"], w])
	for road in city.roads:
		var group := 1 if OVER_BUILDINGS.has(road["tier"]) else 0
		var ends := [road["pts"][0], road["pts"][road["pts"].size() - 1]]
		var found := Vector2.ZERO
		for e in 2:
			for other in at[[group, Vector2i((ends[e] / JOIN_SNAP_M).round())]]:
				if other[0] != road["id"]:
					found[e] = maxf(found[e], other[1])
		_joins[road["id"]] = found

func _draw_overlays(ci: CanvasItem) -> void:
	if show_public:
		for z in city.public_zones:   # outlines only: cheap, and exact even for zones with holes
			var col: Color = PUBLIC_COLORS[z["kind"]]
			ci.draw_polyline(z["outer"], col, 1.4)
			for h in z["holes"]:
				ci.draw_polyline(h, col, 1.4)
		for c in city.crosswalks:
			var d: Vector2 = c["dir"]
			var nrm := Vector2(-d.y, d.x) * (float(c["len"]) / 2)
			ci.draw_line(c["c"] - nrm, c["c"] + nrm, Color.WHITE, 2.5)
	if night and show_markers:
		for p in city.dead_ends:
			ci.draw_circle(p, 9.0, Color("ff4d4d"))
		for p in city.dark_spots:
			ci.draw_arc(p, 30.0, 0.0, TAU, 24, Color("b46cff"), 5.0)

static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
