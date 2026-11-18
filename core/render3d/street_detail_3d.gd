## G2 / VS2A: the street itself. A concrete kerb along both edges of every
## arterial and residential road, drawn from KerbRuns: one continuous run per
## edge, mitred through bends, turning each street corner in a rounded
## return, dropped with a sloped flare at driveways and lot entrances, flush
## at crosswalk ramps (a darker grooved plate on the sidewalk behind), and
## painted red by hydrants. A gutter band runs inside it. On arterials, LA's
## white parking ticks and a meter per space. On the asphalt: drain grates,
## manhole covers, patches and tar snakes (RoadWear3D). Drawn into the chunk
## meshes; each run belongs to the chunk that holds its first point.
class_name StreetDetail3D
extends RefCounted

const KERB_W := 0.18
const GUTTER_W := 0.45
const KERB := Color("cfcac0")
const KERB_RED := Color("b8392e")
const GUTTER := Color("a9a59c")
const RAMP_PLATE := Color("9c978d")   # the grooved ramp: darker than the sidewalk (no yellow pads in the 90s)
const TICK := Color("e6e4dc")
const METER := Color("6f7479")
const METER_POST := Color("4a4d50")
const OWN_REACH := CityMesh3D.CHUNK_M * 0.75 + 12.0   # a road this near a chunk's centre may start a run in it

## Kerbs, gutters and road wear within sqrt(r2) of `centre`.
static func add(m: CityMesh3D, city: CityData, real: CityReal, centre: Vector2, r2: float) -> void:
	var reach := sqrt(r2) if m.only == CityMesh3D.ALL else OWN_REACH   # a chunk build only needs the runs it owns
	var whole: CityData = city.get_meta("whole", city)   # a chunk slice: work kerbs out from the whole city, so chunks agree
	var whole_real: CityReal = real.get_meta("whole", real)
	var runs := KerbRuns.build(whole, whole_real, centre, reach, m.owns)
	for run in runs:
		draw(m, run)
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		if r["tier"] in KerbRuns.KERBED and CityMesh3D._near(r["pts"], centre, r2):
			RoadWear3D.add(m, r, i, RoadSpace.of(city))

## One run: kerb top, face and back, and the gutter, piece by piece; then its ramps and meters.
static func draw(m: CityMesh3D, run: Dictionary) -> void:
	var pts: PackedVector2Array = run["pts"]
	var out: PackedVector2Array = run["out"]
	var h: PackedFloat32Array = run["h"]
	var red: PackedByteArray = run["red"]
	var st := m._tool(pts[0])
	var plain := SurfaceDetail.mark(KERB, SurfaceDetail.SIDEWALK)
	var gutter := SurfaceDetail.mark(GUTTER, SurfaceDetail.SIDEWALK)
	var road := StreetLevels.ROAD
	var gy := StreetLevels.GUTTER
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var wa := out[k] * KERB_W
		var wb := out[k + 1] * KERB_W
		var ga := out[k] * GUTTER_W
		var gb := out[k + 1] * GUTTER_W
		var col: Color = KERB_RED if red[k] == 1 else plain
		var n := (out[k] + out[k + 1]).normalized()
		var face := Vector3(-n.x, 0, -n.y)
		m._quad(st, [m._v(a, h[k]), m._v(b, h[k + 1]), m._v(b + wb, h[k + 1]), m._v(a + wa, h[k])], Vector3.UP, col.lightened(0.06))
		m._quad(st, [m._v(a, road), m._v(b, road), m._v(b, h[k + 1]), m._v(a, h[k])], face, col.darkened(0.12))
		m._quad(st, [m._v(b + wb, 0.0), m._v(a + wa, 0.0), m._v(a + wa, h[k]), m._v(b + wb, h[k + 1])], -face, col.darkened(0.2))
		m._quad(st, [m._v(a - ga, gy), m._v(b - gb, gy), m._v(b, gy), m._v(a, gy)], Vector3.UP, gutter)
	for r in run["ramps"]:   # [point on the kerb line, along the kerb, width, depth, towards the sidewalk]
		var c: Vector2 = r[0]
		var back: Vector2 = r[4]
		var along: Vector2 = back.orthogonal() * float(r[2]) * 0.5   # square to the kerb (the data's own direction can be off)
		var near := c + back * KERB_W
		var far := c + back * (KERB_W + float(r[3]) * 0.6)
		m._quad(st, [m._v(near - along, StreetLevels.RAMP), m._v(near + along, StreetLevels.RAMP), m._v(far + along, StreetLevels.RAMP), m._v(far - along, StreetLevels.RAMP)],
			Vector3.UP, SurfaceDetail.mark(RAMP_PLATE, SurfaceDetail.SIDEWALK))
	for p in run["meters"]:   # [point, along, towards the sidewalk]
		var at: Vector2 = p[0]
		var o: Vector2 = p[2]
		RoadWear3D._rect(m, at - o * 1.1, o, Vector2(0.45, 0.06), TICK)
		_meter(m, at + o * (KERB_W + 0.45))

## G4: a parking meter on the sidewalk by each space: a post and its head.
static func _meter(m: CityMesh3D, p: Vector2) -> void:
	CityDetail3D._box(m, p, Vector3(0.07, 1.15, 0.07), 0.0, METER_POST)
	StreetClutter3D._raised(m, p, Vector3(0.2, 0.32, 0.16), 1.15, 0.0, METER)
