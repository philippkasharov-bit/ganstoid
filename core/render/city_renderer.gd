## City batch C1 demo: draws a CityData (areas, river, rail, roads by tier) in
## world metres. Render layer only: reads the data, never changes it.
## Day palette = road map; night palette = lit boulevards/freeways, dim locals,
## dark alleys/hills, plus gameplay markers (cul-de-sacs, dark spots).
class_name CityRenderer
extends Node2D

const DRAW_ORDER: Array[String] = ["trail", "path", "alley", "svc", "hill", "res", "art", "ramp", "fwy"]
const WIDTH := {"fwy": 26.0, "ramp": 6.0, "art": 14.0, "res": 6.0, "alley": 3.0, "path": 2.5, "svc": 7.0, "hill": 5.0, "trail": 2.5}
const CASING := {"fwy": 6.0, "art": 4.0}
const BUILDING_DAY := {"house": Color("d9c7a8"), "apartments": Color("cdb48f"), "commercial": Color("c9b9a4"), "industrial": Color("b9b4c2"),
	"garage": Color("d8d2c4"), "civic": Color("c7a98f"), "building": Color("cfc3ad")}
const BUILDING_NIGHT := {"house": Color("232733"), "apartments": Color("2a2c38"), "commercial": Color("2b2a33"), "industrial": Color("1e2029"),
	"garage": Color("1c1e26"), "civic": Color("2e2a30"), "building": Color("252833")}
const DAY := {
	"bg": Color("f1ebde"), "hills": Color("e1e7d1"), "mountains": Color("c3cfb5"), "park": Color("c7dbb3"),
	"airfield": Color("e4e0d4"), "foothill": Color("ede4d2"), "industrial": Color("dcd8e2"), "downtown": Color("ddd0b6"), "commercial": Color("e6d9c0"),
	"river": Color("c4cfd6"), "rail": Color("7d7468"),
	"fwy": Color("f39a35"), "fwy_c": Color("9b5310"), "ramp": Color("e08a2c"), "art": Color("fffaf0"), "art_c": Color("b9a37a"),
	"res": Color("b5ac99"), "alley": Color("c2baa9"), "path": Color("8c7a58"), "svc": Color("a49eb2"), "hill": Color("a89d82"), "trail": Color("9b8357"),
}
const NIGHT := {
	"bg": Color("151a26"), "hills": Color("0b0f14"), "mountains": Color("080b0f"), "park": Color("0b130d"),
	"airfield": Color("10131c"), "foothill": Color("141824"), "industrial": Color("111420"), "downtown": Color("2a2228"), "commercial": Color("231f26"),
	"river": Color("090c12"), "rail": Color("1d1c22"),
	"fwy": Color("ffc066"), "fwy_c": Color("3b2a14"), "ramp": Color("a7782f"), "art": Color("f3a443"), "art_c": Color("6b4a1a"),
	"res": Color("3d4054"), "alley": Color("0a0b10"), "path": Color("15161c"), "svc": Color("2a2d3e"), "hill": Color("262a33"), "trail": Color("1b1a17"),
}

var city: CityData
var night := false:
	set(v):
		night = v
		queue_redraw()
var show_public := false:   # overlay: where civilians may walk (sidewalks, crosswalks, alleys, parks)
	set(v):
		show_public = v
		queue_redraw()
var show_markers := true:
	set(v):
		show_markers = v
		queue_redraw()

func _draw() -> void:
	if city == null:
		return
	var pal: Dictionary = NIGHT if night else DAY
	draw_rect(Rect2(Vector2.ZERO, Vector2(city.size_m, city.size_m)), pal["bg"])
	_draw_areas(pal)
	_draw_water_and_rail(pal)
	_draw_buildings()
	for tier in DRAW_ORDER:
		_draw_tier(tier, pal)
	if show_public:
		_draw_public()
	if night and show_markers:
		_draw_markers()

func _draw_areas(pal: Dictionary) -> void:
	for area in city.areas:
		var col: Color = pal.get(area["kind"], pal["bg"])
		var poly: PackedVector2Array = area["poly"]
		if poly.size() > 2 and poly[0] == poly[poly.size() - 1]:
			poly = poly.slice(0, poly.size() - 1)
		if Geometry2D.triangulate_polygon(poly).size() > 0:
			draw_colored_polygon(poly, col)

func _draw_buildings() -> void:
	var cols: Dictionary = BUILDING_NIGHT if night else BUILDING_DAY
	for b in city.buildings:
		var poly: PackedVector2Array = b["poly"]
		var open_poly := poly.slice(0, poly.size() - 1) if poly[0] == poly[poly.size() - 1] else poly
		if Geometry2D.triangulate_polygon(open_poly).is_empty():
			continue
		var col: Color = cols.get(b["kind"], cols["building"])
		draw_colored_polygon(open_poly, col)
		draw_polyline(poly, col.darkened(0.3), 1.0)

func _draw_water_and_rail(pal: Dictionary) -> void:
	draw_polyline(city.river, pal["river"].darkened(0.15), 70.0)
	draw_polyline(city.river, pal["river"], 46.0)
	for line in city.rail:
		for i in range(0, line.size() - 1):
			draw_dashed_line(line[i], line[i + 1], pal["rail"], 3.0, 14.0)

func _draw_tier(tier: String, pal: Dictionary) -> void:
	var w: float = WIDTH[tier]
	for road in city.roads:
		if road["tier"] != tier:
			continue
		var pts: PackedVector2Array = road["pts"]
		if tier == "alley":   # dashed so alleys never read as streets
			for i in range(0, pts.size() - 1):
				draw_dashed_line(pts[i], pts[i + 1], pal[tier], w, 7.0)
			continue
		if CASING.has(tier):
			draw_polyline(pts, pal[tier + "_c"], w + CASING[tier])
		draw_polyline(pts, pal[tier], w)

func _draw_markers() -> void:
	for p in city.dead_ends:
		draw_circle(p, 9.0, Color("ff4d4d"))
	for p in city.dark_spots:
		draw_arc(p, 30.0, 0.0, TAU, 24, Color("b46cff"), 5.0)

const PUBLIC_COLORS := {"sidewalk": Color(0.1, 0.6, 1.0, 0.75), "alley": Color(1.0, 0.55, 0.1, 0.8), "path": Color(0.2, 0.85, 0.4, 0.8), "park": Color(0.3, 0.8, 0.3, 0.45)}

func _draw_public() -> void:   # outlines only: cheap, and exact even for zones with holes
	for z in city.public_zones:
		var col: Color = PUBLIC_COLORS[z["kind"]]
		draw_polyline(z["outer"], col, 1.4)
		for h in z["holes"]:
			draw_polyline(h, col, 1.4)
	for c in city.crosswalks:
		var d: Vector2 = c["dir"]
		var n := Vector2(-d.y, d.x) * (float(c["len"]) / 2)
		draw_line(c["c"] - n, c["c"] + n, Color.WHITE, 2.5)
