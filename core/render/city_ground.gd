## MR2: draws what is really on the ground (CityReal): lots, surfaces, fences,
## trees, street furniture and marked crossings. Split from CityRenderer, which
## owns the layers and the level of detail; these are only the painters.
class_name CityGround
extends RefCounted

const DAY := {
	"lot_line": Color(0.42, 0.38, 0.3, 0.55),
	"parking": Color("c3c1bb"), "vacant": Color("d9cfb6"), "open": Color("c7dbb3"),
	"plaza": Color("ddd8cc"), "grass": Color("c2d6a8"), "park": Color("c7dbb3"), "garden": Color("b9d3a0"), "pitch": Color("a9cf95"),
	"sports": Color("cfdcc0"), "playground": Color("e3d3a6"), "school": Color("e9e0c9"), "hospital": Color("ecdcd6"),
	"cemetery": Color("c5d2b4"), "construction": Color("d6c8a4"), "railyard": Color("cfcbd2"), "water": Color("a9c6d8"),
	"pool": Color("8fc7e0"), "sand": Color("e6dcb8"), "scrub": Color("c3cfa6"), "wood": Color("a9c696"),
	"fence": Color("7f7a70"), "wall": Color("5f5b54"), "hedge": Color("7fa46a"), "rail": Color("8a8a8a"), "gate": Color("9a8f7c"),
	"tree": Color(0.36, 0.56, 0.3, 0.8), "tree_rim": Color(0.25, 0.42, 0.22, 0.9),
	"signal": Color("3a3a3a"), "stop": Color("c0392b"), "bus_stop": Color("2f6fb5"), "lamp": Color("6b6b6b"),
	"lamp_glow": Color(1, 1, 1, 0.0), "hydrant": Color("d6452f"), "bench": Color("8a6a45"), "bin": Color("4f5a4f"),
	"zebra": Color(0.97, 0.97, 0.94, 0.9),
}
const NIGHT := {
	"lot_line": Color(0.5, 0.52, 0.6, 0.18),
	"parking": Color("1c1f29"), "vacant": Color("181a20"), "open": Color("0b130d"),
	"plaza": Color("22252e"), "grass": Color("0e1811"), "park": Color("0b130d"), "garden": Color("0e1a11"), "pitch": Color("10200f"),
	"sports": Color("121a14"), "playground": Color("1f1d17"), "school": Color("1c1c22"), "hospital": Color("211c20"),
	"cemetery": Color("0d140f"), "construction": Color("1d1a14"), "railyard": Color("15161c"), "water": Color("0a1018"),
	"pool": Color("123244"), "sand": Color("1d1b15"), "scrub": Color("0e150f"), "wood": Color("0a120b"),
	"fence": Color("3a3d48"), "wall": Color("2b2d36"), "hedge": Color("14241a"), "rail": Color("33353d"), "gate": Color("3d3a35"),
	"tree": Color(0.05, 0.12, 0.07, 0.85), "tree_rim": Color(0.03, 0.08, 0.05, 0.9),
	"signal": Color("d8d8d8"), "stop": Color("a23428"), "bus_stop": Color("5a9be0"), "lamp": Color("ffe9b0"),
	"lamp_glow": Color(1.0, 0.86, 0.55, 0.13), "hydrant": Color("8a2e22"), "bench": Color("4a3d2c"), "bin": Color("2c332c"),
	"zebra": Color(0.75, 0.76, 0.8, 0.55),
}
## Parcel uses that show as ground; the rest are just a lot line around a building.
const LOT_FILLS := ["parking", "vacant", "open"]
const TREE_R := 2.6
const LAMP_GLOW_R := 9.0
const POINT_R := {"signal": 0.45, "stop": 0.4, "bus_stop": 0.6, "lamp": 0.3, "hydrant": 0.3, "bench": 0.5, "bin": 0.3}

## Every palette key a painter can ask for (checked by verify_render_palette).
static func KEYS() -> Array:
	return DAY.keys()

static func lots(ci: CanvasItem, items: Array, night: bool) -> void:
	var pal: Dictionary = NIGHT if night else DAY
	for lot in items:
		if LOT_FILLS.has(lot["use"]):
			_fill(ci, lot["poly"], pal[lot["use"]])

static func lot_lines(ci: CanvasItem, items: Array, night: bool) -> void:
	var col: Color = (NIGHT if night else DAY)["lot_line"]
	for lot in items:
		var poly: PackedVector2Array = lot["poly"]
		ci.draw_polyline(poly, col, 0.18)
		ci.draw_line(poly[poly.size() - 1], poly[0], col, 0.18)

static func surfaces(ci: CanvasItem, items: Array, night: bool) -> void:
	var pal: Dictionary = NIGHT if night else DAY
	for s in items:
		_fill(ci, s["poly"], pal.get(s["kind"], pal["plaza"]))

static func crossings(ci: CanvasItem, items: Array, night: bool) -> void:
	var col: Color = (NIGHT if night else DAY)["zebra"]
	for c in items:
		if c["markings"] in ["no", "unmarked", ""]:
			continue
		var pts: PackedVector2Array = c["pts"]
		for i in pts.size() - 1:
			ci.draw_dashed_line(pts[i], pts[i + 1], col, 3.0, 0.6)   # continental stripes across the roadway

## DT1: primitive props (boxes, discs, lines) for everything on the street,
## shaped enough to read at a glance; real models replace them later.
static func trees(ci: CanvasItem, items: PackedVector2Array, night: bool) -> void:
	var pal: Dictionary = NIGHT if night else DAY
	for p in items:
		var h := absi(hash(p))
		var r := TREE_R * (0.8 + float(h % 40) / 100.0)
		for k in 3:   # a clump of canopy, not a coin
			var o := Vector2.from_angle(float((h >> (k * 4)) % 628) / 100.0) * r * 0.35
			ci.draw_circle(p + o, r * 0.75, pal["tree"])
		ci.draw_circle(p, r * 0.35, pal["tree_rim"])

static func details(ci: CanvasItem, barriers: Array, points: Array, night: bool) -> void:
	var pal: Dictionary = NIGHT if night else DAY
	for b in barriers:
		_barrier(ci, b, pal)
	for p in points:
		if p["kind"] in ["signal", "stop", "bus_stop"]:
			continue   # MP3b: lights and stop signs are drawn live at junctions (StreetFurniture); no buses
		_prop(ci, p["kind"], p["p"], pal, night)

static func _barrier(ci: CanvasItem, b: Dictionary, pal: Dictionary) -> void:
	var pts: PackedVector2Array = b["pts"]
	var col: Color = pal[b["kind"]]
	match b["kind"]:
		"wall":
			ci.draw_polyline(pts, col.darkened(0.35), 0.45)
			ci.draw_polyline(pts, col, 0.3)
		"hedge":
			ci.draw_polyline(pts, col, 0.9)
			ci.draw_polyline(pts, col.darkened(0.2), 0.4)
		_:
			ci.draw_polyline(pts, col, 0.12)   # fence, rail, gate: a thin line with posts
			for i in pts.size() - 1:
				var seg := pts[i].distance_to(pts[i + 1])
				var n := int(seg / 2.5)
				for k in n + 1:
					ci.draw_rect(Rect2(pts[i].lerp(pts[i + 1], float(k) / maxf(1, n)) - Vector2(0.1, 0.1), Vector2(0.2, 0.2)), col.darkened(0.3))

static func _prop(ci: CanvasItem, kind: String, at: Vector2, pal: Dictionary, night: bool) -> void:
	var turn := float(absi(hash(at)) % 628) / 100.0
	var f := Vector2.from_angle(turn)
	var col: Color = pal[kind]
	match kind:
		"lamp":
			if night:
				ci.draw_circle(at + f * 1.3, LAMP_GLOW_R, pal["lamp_glow"])
			ci.draw_line(at, at + f * 1.3, col.darkened(0.2), 0.12)   # arm
			ci.draw_rect(Rect2(at - Vector2(0.15, 0.15), Vector2(0.3, 0.3)), col.darkened(0.3))   # pole
			ci.draw_circle(at + f * 1.3, 0.22, Color("fff3c4") if night else col.lightened(0.3))   # head
		"bench":
			var side := f.orthogonal()
			ci.draw_colored_polygon(PackedVector2Array([at - f * 0.8 - side * 0.25, at + f * 0.8 - side * 0.25, at + f * 0.8 + side * 0.25, at - f * 0.8 + side * 0.25]), col)
			ci.draw_line(at - f * 0.8 + side * 0.25, at + f * 0.8 + side * 0.25, col.darkened(0.35), 0.12)   # backrest
		"hydrant":
			ci.draw_circle(at, 0.22, col)
			ci.draw_line(at - f * 0.3, at + f * 0.3, col.darkened(0.3), 0.1)   # outlets
			ci.draw_circle(at, 0.1, col.lightened(0.3))
		"bin":
			ci.draw_rect(Rect2(at - Vector2(0.28, 0.28), Vector2(0.56, 0.56)), col)
			ci.draw_rect(Rect2(at - Vector2(0.18, 0.18), Vector2(0.36, 0.36)), col.darkened(0.3))
		_:
			ci.draw_circle(at, POINT_R.get(kind, 0.3), col)

## DT1: painted stalls in parking lots: rows across the lot's long side,
## 2.7 m bays, 5.5 m deep, a 7 m aisle between row pairs.
static func parking_stalls(ci: CanvasItem, items: Array, night: bool) -> void:
	var col := Color(1, 1, 1, 0.35 if night else 0.75)
	for s in items:
		if s["kind"] != "parking":
			continue
		var poly: PackedVector2Array = s["poly"]
		if poly.size() < 4:
			continue
		var axis := Vector2.RIGHT
		var longest := 0.0
		for i in poly.size() - 1:
			var e := poly[i + 1] - poly[i]
			if e.length() > longest:
				longest = e.length()
				axis = e / e.length()
		var across := axis.orthogonal()
		var lo := INF
		var hi := -INF
		var a_lo := INF
		var a_hi := -INF
		for p in poly:
			lo = minf(lo, p.dot(across))
			hi = maxf(hi, p.dot(across))
			a_lo = minf(a_lo, p.dot(axis))
			a_hi = maxf(a_hi, p.dot(axis))
		if (hi - lo) * (a_hi - a_lo) > 60000.0:
			continue   # huge lots: skip (thousands of lines)
		var band := lo + 1.0
		while band + 5.5 <= hi:
			var x := a_lo
			while x <= a_hi:
				var p0 := axis * x + across * band
				var p1 := axis * x + across * (band + 5.5)
				for piece in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([p0, p1]), poly):
					ci.draw_polyline(piece, col, 0.12)
				x += 2.7
			band += 5.5 + (7.0 if int((band - lo) / 12.5) % 2 == 0 else 0.0)

static func _fill(ci: CanvasItem, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty():
		ci.draw_colored_polygon(poly, col)
