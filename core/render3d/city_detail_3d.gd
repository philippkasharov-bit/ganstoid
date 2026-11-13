## D2: the ground-level detail that makes it a real LA street, from the
## surveyed data (CityReal): every house and apartment lot is a yard of
## grass (lush, dry or patchy by the lot), shops and works sit on concrete
## and asphalt; parks, pitches, playgrounds, plazas, parking lots and
## backyard pools as they are mapped; walls, fences and hedges along their
## lines; zebra crossings where they are painted; hydrants, benches and
## bins. D4: lane lines on the big roads, painted crosswalks at junctions,
## concrete driveway aprons across the sidewalk. Drawn into the city's chunk
## meshes (one material); ground below the roads, paint on top of them.
## Trees and the overhead power lines come back as MultiMeshes.
class_name CityDetail3D
extends RefCounted

const LOT_H := 0.008
const SURFACE_H := 0.012
const STRIPE_H := 0.045
const YARDS := [Color("8fae6a"), Color("9cb071"), Color("b3ad7a"), Color("a7b47c"), Color("c2b98c")]   # lush .. dry
const LOT_COL := {"commercial": Color("b9b4aa"), "industrial": Color("a8a59e"), "parking": Color("77746f"), "civic": Color("c8c2b2"), "open": Color("bdb48f")}
const SURFACE_COL := {"park": Color("8fb36a"), "grass": Color("97b872"), "pitch": Color("7fae5c"), "school": Color("c9b79a"),
	"sports": Color("b0704a"), "parking": Color("6f6d69"), "pool": Color("4fa6c9"), "plaza": Color("cfc6b4"), "playground": Color("c46a3a"),
	"water": Color("5b8fb0"), "railyard": Color("8a7f70"), "vacant": Color("c8b98f")}
const BARRIER := {"wall": [1.8, 0.22, Color("d9cdb5")], "fence": [1.3, 0.06, Color("5d6166")], "hedge": [1.3, 0.7, Color("5f8a4a")],
	"gate": [1.4, 0.08, Color("3a3d42")], "rail": [1.0, 0.08, Color("6d7075")]}
const LOT_SURFACE := {"house": SurfaceDetail.GRASS, "apartments": SurfaceDetail.GRASS, "commercial": SurfaceDetail.SIDEWALK, "civic": SurfaceDetail.SIDEWALK,
	"industrial": SurfaceDetail.ASPHALT, "parking": SurfaceDetail.ASPHALT, "open": SurfaceDetail.DIRT}   # TX1
const SURFACE_OF := {"park": SurfaceDetail.GRASS, "grass": SurfaceDetail.GRASS, "pitch": SurfaceDetail.GRASS, "school": SurfaceDetail.SIDEWALK,
	"parking": SurfaceDetail.ASPHALT, "plaza": SurfaceDetail.SIDEWALK, "vacant": SurfaceDetail.DIRT, "railyard": SurfaceDetail.DIRT}
const POINT := {"hydrant": [Vector3(0.3, 0.75, 0.3), Color("d6452f")], "bench": [Vector3(1.6, 0.5, 0.5), Color("8a6a45")], "bin": [Vector3(0.55, 0.95, 0.55), Color("4f5a4f")]}

## Adds the detail within `radius` of `centre` to the city builder `m`.
static func add(m: CityMesh3D, city: CityData, real: CityReal, centre: Vector2, radius: float) -> void:
	var r2 := radius * radius
	_paint(m, city, centre, r2)
	StreetDetail3D.add(m, city, real, centre, r2)   # G2: kerbs, gutters, road wear
	for lot in real.lots:
		if CityMesh3D._near(lot["poly"], centre, r2):
			m._flat_poly(CityMesh3D._open(lot["poly"]), LOT_H, SurfaceDetail.mark(_lot_colour(lot), LOT_SURFACE.get(lot["use"], SurfaceDetail.NONE)))
	for s in real.surfaces:
		if SURFACE_COL.has(s["kind"]) and CityMesh3D._near(s["poly"], centre, r2):
			m._flat_poly(CityMesh3D._open(s["poly"]), SURFACE_H, SurfaceDetail.mark(SURFACE_COL[s["kind"]], SURFACE_OF.get(s["kind"], SurfaceDetail.NONE)))
	for b in real.barriers:
		if BARRIER.has(b["kind"]) and CityMesh3D._near(b["pts"], centre, r2):
			_barrier(m, b["pts"], BARRIER[b["kind"]])
	for c in real.crossings:
		if c["markings"] != "no" and CityMesh3D._near(c["pts"], centre, r2):
			_zebra(m, c["pts"])
	for p in real.points:
		if POINT.has(p["kind"]) and p["p"].distance_squared_to(centre) < r2:
			var spec: Array = POINT[p["kind"]]
			_box(m, p["p"], spec[0], absf(fmod(p["p"].x * 0.37, PI)), spec[1])

static func _lot_colour(lot: Dictionary) -> Color:
	if lot["use"] in ["house", "apartments"]:
		var poly: PackedVector2Array = lot["poly"]
		return YARDS[absi(int(poly[0].x * 13.0 + poly[0].y * 7.0)) % YARDS.size()]
	return LOT_COL.get(lot["use"], Color("c4bca8"))

## A wall, fence or hedge along a line: a low box per segment, with a cap.
static func _barrier(m: CityMesh3D, pts: PackedVector2Array, spec: Array) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if a.distance_to(b) < 0.05:
			continue
		var n := (b - a).orthogonal().normalized() * float(spec[1]) * 0.5
		_prism(m, [a - n, b - n, b + n, a + n], spec[0], spec[2])

## Zebra stripes across the road: white bars along the traffic, a metre apart.
static func _zebra(m: CityMesh3D, pts: PackedVector2Array) -> void:
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var length := a.distance_to(b)
	if length < 2.0:
		return
	var along := (b - a) / length
	var traffic := along.orthogonal() * 1.4
	var bars := int(length / 1.0)
	for k in bars:
		var c := a + along * (k + 0.5) * (length / bars)
		var half := along * 0.25
		m._quad(m._tool(c), [m._v(c - half - traffic, STRIPE_H), m._v(c + half - traffic, STRIPE_H), m._v(c + half + traffic, STRIPE_H), m._v(c - half + traffic, STRIPE_H)], Vector3.UP, Color("efeee8"))

## A small object: a box of `size`, turned `angle`, standing at `p`.
static func _box(m: CityMesh3D, p: Vector2, size: Vector3, angle: float, col: Color) -> void:
	var x := Vector2.from_angle(angle) * size.x * 0.5
	var z := Vector2.from_angle(angle).orthogonal() * size.z * 0.5
	_prism(m, [p - x - z, p + x - z, p + x + z, p - x + z], size.y, col)

## Four sides and a top over the footprint `c` (4 map points), `h` tall.
static func _prism(m: CityMesh3D, c: Array, h: float, col: Color) -> void:
	var st := m._tool(c[0])
	for i in 4:
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % 4]
		var e := b - a
		m._quad(st, [m._v(a, 0.0), m._v(b, 0.0), m._v(b, h), m._v(a, h)], Vector3(e.y, 0, -e.x).normalized(), col.darkened(0.06 * (i % 2)))
	m._quad(st, [m._v(c[0], h), m._v(c[1], h), m._v(c[2], h), m._v(c[3], h)], Vector3.UP, col.lightened(0.05))

const PAINT_H := 0.047
const PAINT := Color("ecebe4")
const DASH_M := 3.0
const DASH_GAP_M := 6.0

## D4: lane dashes, junction crosswalks and driveway aprons.
static func _paint(m: CityMesh3D, city: CityData, centre: Vector2, r2: float) -> void:
	for r in city.roads:
		if r["tier"] in ["art", "fwy"] and CityMesh3D._near(r["pts"], centre, r2):
			_lanes(m, r)
	for x in _junctions().near(centre, sqrt(r2)):
		if x["kind"] == "signal":   # P1: LA paints its crossings at signals (the nav data's walk zones are not paint)
			for leg in x["legs"]:
				_crossing_at(m, x["c"], leg[0], leg[1])
	for d in city.driveways:
		if d["c"].distance_squared_to(centre) < r2:
			var out: Vector2 = d["dir"]
			var side := out.orthogonal() * float(d["w"]) * 0.5
			var c: Vector2 = d["c"]
			var far := c + out * float(d["len"])
			m._quad(m._tool(c), [m._v(c - side, 0.03), m._v(c + side, 0.03), m._v(far + side, 0.03), m._v(far - side, 0.03)], Vector3.UP, SurfaceDetail.mark(Color("d6d1c6"), SurfaceDetail.SIDEWALK))

## White dashes between the lanes on each side of the middle.
static func _lanes(m: CityMesh3D, r: Dictionary) -> void:
	var lanes := maxi(2, str(r.get("lanes", "2")).to_int())
	var w: float = r.get("w", CityMesh3D.ROAD_W.get(r["tier"], 6.0))
	var per_side := lanes / 2
	var pts: PackedVector2Array = r["pts"]
	for k in range(1, per_side):
		for side in [-1.0, 1.0]:
			_dashes(m, pts, side * k * w / lanes)

static func _dashes(m: CityMesh3D, pts: PackedVector2Array, offset: float) -> void:
	var run := 0.0
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var length := seg.length()
		if length < 0.1:
			continue
		var dir := seg / length
		var n := dir.orthogonal()
		while run < length:
			var a := pts[i] + dir * run + n * offset
			var b := pts[i] + dir * minf(run + DASH_M, length) + n * offset
			var t := n * 0.07
			m._quad(m._tool(a), [m._v(a - t, PAINT_H), m._v(b - t, PAINT_H), m._v(b + t, PAINT_H), m._v(a + t, PAINT_H)], Vector3.UP, PAINT)
			run += DASH_M + DASH_GAP_M
		run -= length

static var _j: Junctions

static func _junctions() -> Junctions:
	if _j == null:
		_j = Junctions.load_file()
	return _j

## Zebra across one leg of a junction, between its stop line and the corner.
static func _crossing_at(m: CityMesh3D, c: Vector2, into: Vector2, w: float) -> void:
	var mid := c - into * (w * 0.5 + 1.2)
	var across := into.orthogonal() * w * 0.5
	_zebra(m, PackedVector2Array([mid - across, mid + across]))
