## G2: the street itself. A concrete kerb along both edges of every
## arterial and residential road (its face toward the traffic, painted red
## by hydrants), a gutter band inside it, both broken wherever another road,
## an alley or a driveway comes in (the corner shows as a kerb cut). On the
## asphalt: drain grates in the gutter, manhole covers in the lanes, darker
## patches and black tar-snake crack seals, and LA's white parking ticks
## along the kerb of the big roads. Drawn into the chunk meshes.
class_name StreetDetail3D
extends RefCounted

const KERB_H := 0.12
const KERB_W := 0.18
const GUTTER_W := 0.45
const PIECE_M := 2.0
const CORNER_M := 2.5          # kerb kept this far clear of a crossing road's edge
const CELL_M := 24.0
const KERBED := ["art", "res"]
const CROSSING := ["art", "res", "svc", "alley", "drive", "aisle", "ramp", "hill"]
const KERB := Color("cfcac0")
const KERB_RED := Color("b8392e")
const GUTTER := Color("a9a59c")
const TICK := Color("e6e4dc")
const METER := Color("6f7479")
const METER_POST := Color("4a4d50")
const RED_M := 4.5
const DRIVE_M := 3.0           # kerb cut this far either side of a driveway             # no parking this close to a hydrant
const ROAD_Y := 0.04

## Kerbs, gutters and road wear within sqrt(r2) of `centre`.
static func add(m: CityMesh3D, city: CityData, real: CityReal, centre: Vector2, r2: float) -> void:
	var grid := _grid(city, centre, r2)
	var hydrants := {}
	for d in city.driveways:
		if d["c"].distance_squared_to(centre) < r2:
			_bucket(grid, d["c"], d["c"], DRIVE_M - CORNER_M, [d["c"], d["c"], DRIVE_M - CORNER_M, -1])   # a driveway is a kerb cut
	for p in real.points:
		if p["kind"] == "hydrant" and p["p"].distance_squared_to(centre) < r2:
			_bucket(hydrants, p["p"], p["p"], RED_M, p["p"])
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		if r["tier"] in KERBED and CityMesh3D._near(r["pts"], centre, r2):
			_kerbs(m, r, i, grid, hydrants)
			RoadWear3D.add(m, r)

## Every crossing road's segments, bucketed by CELL_M square.
static func _grid(city: CityData, centre: Vector2, r2: float) -> Dictionary:
	var grid := {}
	var reach := sqrt(r2) + 40.0
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		if not r["tier"] in CROSSING or not CityMesh3D._near(r["pts"], centre, reach * reach):
			continue
		var half: float = float(r.get("w", CityMesh3D.ROAD_W.get(r["tier"], 6.0))) * 0.5
		var pts: PackedVector2Array = r["pts"]
		for k in pts.size() - 1:
			_bucket(grid, pts[k], pts[k + 1], half, [pts[k], pts[k + 1], half, i])
	return grid

## Files `item` in every CELL_M square within `half` + CORNER_M of a..b, so one lookup finds it.
static func _bucket(grid: Dictionary, a: Vector2, b: Vector2, half: float, item: Variant) -> void:
	var grow := Vector2.ONE * (half + CORNER_M)
	var lo := Vector2i(((a.min(b) - grow) / CELL_M).floor())
	var hi := Vector2i(((a.max(b) + grow) / CELL_M).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			grid.get_or_add(Vector2i(x, y), []).append(item)

## Is `p` on (or at the corner of) a road other than `own`, or at a driveway?
static func _cut(p: Vector2, own: int, grid: Dictionary) -> bool:
	for item in grid.get(Vector2i((p / CELL_M).floor()), []):
		if item[3] != own:
			var near := Geometry2D.get_closest_point_to_segment(p, item[0], item[1])
			if near.distance_to(p) < float(item[2]) + CORNER_M:
				return true
	return false

## Both edges of road `r`, in runs of kept PIECE_M pieces.
static func _kerbs(m: CityMesh3D, r: Dictionary, own: int, grid: Dictionary, hydrants: Dictionary) -> void:
	var half: float = float(r.get("w", CityMesh3D.ROAD_W.get(r["tier"], 6.0))) * 0.5
	var pts: PackedVector2Array = r["pts"]
	for k in pts.size() - 1:
		var length := pts[k].distance_to(pts[k + 1])
		if length < 0.2:
			continue
		var dir := (pts[k + 1] - pts[k]) / length
		var pieces := maxi(1, ceili(length / PIECE_M))
		for side in [-1.0, 1.0]:
			var out: Vector2 = dir.orthogonal() * side
			for j in pieces:
				var a := pts[k] + dir * length * j / pieces + out * half
				var b := pts[k] + dir * length * (j + 1) / pieces + out * half
				if not _cut((a + b) * 0.5, own, grid):
					var red := _by_hydrant((a + b) * 0.5, hydrants)
					_piece(m, a, b, out, red)
					if r["tier"] == "art" and not red and j % 3 == 0:   # a metered space every ~6 m
						RoadWear3D._rect(m, a - out * 1.1, out, Vector2(0.45, 0.06), TICK)
						_meter(m, a + out * (KERB_W + 0.45))

## G4: a parking meter on the sidewalk by each space: a post and its head.
static func _meter(m: CityMesh3D, p: Vector2) -> void:
	CityDetail3D._box(m, p, Vector3(0.07, 1.15, 0.07), 0.0, METER_POST)
	StreetClutter3D._raised(m, p, Vector3(0.2, 0.32, 0.16), 1.15, 0.0, METER)

static func _by_hydrant(p: Vector2, hydrants: Dictionary) -> bool:
	for h in hydrants.get(Vector2i((p / CELL_M).floor()), []):
		if h.distance_squared_to(p) < RED_M * RED_M:
			return true
	return false

## One kerb piece a..b on the road edge: its top, its face to the road, its gutter.
static func _piece(m: CityMesh3D, a: Vector2, b: Vector2, out: Vector2, red: bool) -> void:
	var st := m._tool(a)
	var w := out * KERB_W
	var g := out * GUTTER_W
	var face := Vector3(-out.x, 0, -out.y)
	var col: Color = KERB_RED if red else SurfaceDetail.mark(KERB, SurfaceDetail.SIDEWALK)
	m._quad(st, [m._v(a, KERB_H), m._v(b, KERB_H), m._v(b + w, KERB_H), m._v(a + w, KERB_H)], Vector3.UP, col.lightened(0.06))
	m._quad(st, [m._v(a, ROAD_Y), m._v(b, ROAD_Y), m._v(b, KERB_H), m._v(a, KERB_H)], face, col.darkened(0.12))
	m._quad(st, [m._v(b + w, 0.0), m._v(a + w, 0.0), m._v(a + w, KERB_H), m._v(b + w, KERB_H)], -face, col.darkened(0.2))
	m._quad(st, [m._v(a - g, ROAD_Y + 0.003), m._v(b - g, ROAD_Y + 0.003), m._v(b, ROAD_Y + 0.003), m._v(a, ROAD_Y + 0.003)], Vector3.UP, SurfaceDetail.mark(GUTTER, SurfaceDetail.SIDEWALK))
