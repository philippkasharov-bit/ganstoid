## City map renderer (C1, MP1, perf pass): draws a CityData (areas, river, rail,
## sidewalks, streets, buildings, elevated freeways) in world metres. Render
## layer only: reads the data, never changes it.
## Performance: the map is split into layers x 12x12 tiles (~500 m), each its own
## canvas item, so Godot only submits tiles on screen; round road joints are
## drawn only where a road actually bends. Day/night switch redraws every tile.
class_name CityRenderer
extends Node2D

const DRAW_ORDER: Array[String] = ["trail", "path", "alley", "svc", "hill", "res", "art"]   # under buildings
const OVER_BUILDINGS: Array[String] = ["ramp", "fwy"]   # elevated: drawn over everything

## Every road tier the map draws (checked against the palettes by verify_render_palette).
static func TIERS_DRAWN() -> Array:
	return DRAW_ORDER + OVER_BUILDINGS
## Fallback widths; MP1 roads carry their real roadway width ("w") and sidewalk+parkway ("side").
const WIDTH := {"fwy": 26.0, "ramp": 6.0, "art": 14.0, "res": 6.0, "alley": 3.0, "path": 2.5, "svc": 7.0, "hill": 5.0, "trail": 2.5}
const CASING := {"fwy": 3.0, "ramp": 2.0}   # elevated roads get a shadowed edge; streets use the kerb instead
const BUILDING_DAY := {"house": Color("d9c7a8"), "apartments": Color("cdb48f"), "commercial": Color("c9b9a4"), "industrial": Color("b9b4c2"),
	"garage": Color("d8d2c4"), "civic": Color("c7a98f"), "building": Color("cfc3ad")}
const BUILDING_NIGHT := {"house": Color("232733"), "apartments": Color("2a2c38"), "commercial": Color("2b2a33"), "industrial": Color("1e2029"),
	"garage": Color("1c1e26"), "civic": Color("2e2a30"), "building": Color("252833")}
const DAY := {
	"bg": Color("f1ebde"), "hills": Color("e1e7d1"), "mountains": Color("c3cfb5"), "park": Color("c7dbb3"),
	"airfield": Color("e4e0d4"), "foothill": Color("ede4d2"), "industrial": Color("dcd8e2"), "downtown": Color("ddd0b6"), "commercial": Color("e6d9c0"),
	"river": Color("c4cfd6"), "rail": Color("7d7468"),
	"fwy": Color("807f7a"), "fwy_c": Color("5b5a56"), "ramp": Color("8a8984"), "ramp_c": Color("6a6964"), "art": Color("8e8d89"), "art_c": Color("74726d"),
	"res": Color("a09d96"), "alley": Color("b3ada2"), "path": Color("8c7a58"), "svc": Color("a49eb2"), "hill": Color("a89d82"), "trail": Color("9b8357"),
	"walk": Color("d6d3cb"), "kerb": Color("b3aea3"),
}
const NIGHT := {
	"bg": Color("151a26"), "hills": Color("0b0f14"), "mountains": Color("080b0f"), "park": Color("0b130d"),
	"airfield": Color("10131c"), "foothill": Color("141824"), "industrial": Color("111420"), "downtown": Color("2a2228"), "commercial": Color("231f26"),
	"river": Color("090c12"), "rail": Color("1d1c22"),
	"fwy": Color("ffc066"), "fwy_c": Color("3b2a14"), "ramp": Color("a7782f"), "ramp_c": Color("2c2414"), "art": Color("f3a443"), "art_c": Color("6b4a1a"),
	"res": Color("3d4054"), "alley": Color("0a0b10"), "path": Color("15161c"), "svc": Color("2a2d3e"), "hill": Color("262a33"), "trail": Color("1b1a17"),
	"walk": Color("23262f"), "kerb": Color("191b22"),
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

var _nodes: Array[Node2D] = []

func _process(_delta: float) -> void:
	if city != null and _nodes.is_empty():
		_build()

func _redraw_all() -> void:
	for n in _nodes:
		n.queue_redraw()

## One node per (layer, tile); node order = draw order (later nodes paint over earlier ones).
func _build() -> void:
	_add_layer(func(ci: CanvasItem, _r: Rect2) -> void: _draw_base(ci), [Rect2()])
	var tiles := _tile_rects()
	var roads := _bucket(city.roads, tiles, func(r: Dictionary) -> Rect2: return _bounds(r["pts"]).grow(r.get("w", WIDTH[r["tier"]]) * 0.5 + r.get("side", 0.0)))
	var blds := _bucket(city.buildings, tiles, func(b: Dictionary) -> Rect2: return Rect2(_bounds(b["poly"]).get_center(), Vector2.ZERO))
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_sidewalks(ci, roads[r]), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_tiers(ci, roads[r], DRAW_ORDER), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_buildings(ci, blds[r]), tiles)
	_add_layer(func(ci: CanvasItem, r: Rect2) -> void: _draw_tiers(ci, roads[r], OVER_BUILDINGS), tiles)
	_add_layer(func(ci: CanvasItem, _r: Rect2) -> void: _draw_overlays(ci), [Rect2()])

func _add_layer(painter: Callable, rects: Array) -> void:
	for rect in rects:
		var n := Node2D.new()
		n.draw.connect(func() -> void: painter.call(n, rect))
		add_child(n)
		_nodes.append(n)

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

## Concrete sidewalk + parkway band each side of every street (MP1), then a darker kerb edge.
func _draw_sidewalks(ci: CanvasItem, roads: Array) -> void:
	var pal := _pal()
	for pass_kerb in [false, true]:
		for road in roads:
			var side: float = road.get("side", 0.0)
			if side > 0.0:
				var w: float = road.get("w", WIDTH[road["tier"]])
				_thick_line(ci, road["pts"], pal["kerb"] if pass_kerb else pal["walk"], w + 0.6 if pass_kerb else w + 2.0 * side)

## Per tier: all edges first, then all fills, so one road's edge never paints over its neighbour.
func _draw_tiers(ci: CanvasItem, roads: Array, tiers: Array[String]) -> void:
	var pal := _pal()
	for tier in tiers:
		if CASING.has(tier):
			for road in roads:
				if road["tier"] == tier:
					_thick_line(ci, road["pts"], pal[tier + "_c"], road.get("w", WIDTH[tier]) + CASING[tier])
		for road in roads:
			if road["tier"] == tier:
				_thick_line(ci, road["pts"], pal[tier], road.get("w", WIDTH[tier]))

func _draw_buildings(ci: CanvasItem, blds: Array) -> void:
	var cols: Dictionary = BUILDING_NIGHT if night else BUILDING_DAY
	for b in blds:
		var poly: PackedVector2Array = b["poly"]
		var open_poly := poly.slice(0, poly.size() - 1) if poly[0] == poly[poly.size() - 1] else poly
		if Geometry2D.triangulate_polygon(open_poly).is_empty():
			continue
		var col: Color = cols.get(b["kind"], cols["building"])
		ci.draw_colored_polygon(open_poly, col)
		ci.draw_polyline(poly, col.darkened(0.3), 0.3)   # wall outline, metres

## A polyline with round joints at its ends and real bends (plain wide polylines notch there).
func _thick_line(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	ci.draw_polyline(pts, col, w)
	var n := pts.size()
	for i in n:
		if i == 0 or i == n - 1 or absf((pts[i] - pts[i - 1]).angle_to(pts[i + 1] - pts[i])) > deg_to_rad(JOINT_TURN_DEG):
			ci.draw_circle(pts[i], w * 0.5, col)

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
