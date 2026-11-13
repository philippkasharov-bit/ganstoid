## R3D1: the whole district in 3D, built once and fast to draw. The map is
## cut into CHUNK_M squares; each square becomes ONE mesh (ground areas,
## sidewalks, roads, every building's walls, roof, windows and door) coloured
## per vertex, so thousands of buildings cost a few dozen draw calls and the
## camera culls the squares it cannot see. Palms are two MultiMeshes for the
## whole district. Reads CityData only; the simulation never sees this.
## Map (x, y) -> 3D (x, height, y), relative to `origin`.
class_name CityMesh3D
extends RefCounted

const CHUNK_M := 160.0
const STOREY_M := 3.2
const ROAD_W := {"fwy": 26.0, "ramp": 6.0, "art": 14.0, "res": 6.0, "alley": 3.0, "path": 2.5, "svc": 7.0, "hill": 5.0, "trail": 2.5, "aisle": 7.3, "drive": 3.7}
const ROAD_COL := {"fwy": Color("75746f"), "ramp": Color("7b7a75"), "art": Color("6f6e6a"), "res": Color("7d7a74"), "alley": Color("8c887f"),
	"path": Color("cfcbc1"), "svc": Color("85837d"), "hill": Color("8f8570"), "trail": Color("9b8357"), "aisle": Color("85837d"), "drive": Color("b8b4aa")}
const AREA_COL := {"park": Color("a9c48f"), "hills": Color("d6dcc4"), "mountains": Color("b9c6a8"), "airfield": Color("dcd8cc"),
	"foothill": Color("e3dac6"), "industrial": Color("d3cfd8"), "downtown": Color("d8cbb0"), "commercial": Color("e1d4ba"), "river": Color("9fb3bf")}
const WALLS := {"house": Color("d9c7a8"), "apartments": Color("cdb48f"), "commercial": Color("c9b9a4"), "industrial": Color("b4b8bc"),
	"garage": Color("d8d2c4"), "civic": Color("c7a98f"), "building": Color("cfc3ad")}
const ROOF := Color("8a7f72")
const SIDEWALK := Color("cbc7be")
const GLASS := Color("3b4a5c")
const DOOR := Color("3a2a1e")
const DOOR_FRAME := Color("e8e2d4")
const CENTRE_LINE := Color("d8b23e")
const DOOR_W := 1.1
const DOOR_H := 2.1

var origin := Vector2.ZERO
var _tools := {}   # chunk Vector2i -> SurfaceTool

## Every chunk mesh plus the palms, as nodes ready to add under a Node3D.
static func build(city: CityData, centre: Vector2, radius: float) -> Array[Node3D]:
	var b := CityMesh3D.new()
	b.origin = centre
	var r2 := radius * radius
	for area in city.areas:
		if _near(area["poly"], centre, r2):
			b._area(area)
	for road in city.roads:
		if _near(road["pts"], centre, r2):
			b._road(road)
	for bld in city.buildings:
		if _near(bld["poly"], centre, r2):
			b._building(bld)
	var out: Array[Node3D] = b._commit()
	var wells := PackedVector2Array()
	for w in city.tree_wells:
		if w.distance_squared_to(centre) < r2:
			wells.append(w)
	out.append_array(b._palms(wells))
	return out

static func _near(pts: PackedVector2Array, c: Vector2, r2: float) -> bool:
	for p in pts:
		if p.distance_squared_to(c) < r2:
			return true
	return false

func _v(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x - origin.x, h, p.y - origin.y)

func _tool(at: Vector2) -> SurfaceTool:
	var k := Vector2i(((at - origin) / CHUNK_M).floor())
	if not _tools.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[k] = st
	return _tools[k]

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

## A quad a-b-c-d (any winding; the material draws both sides).
func _quad(st: SurfaceTool, q: Array, n: Vector3, col: Color) -> void:
	_tri(st, q[0], q[1], q[2], n, col)
	_tri(st, q[0], q[2], q[3], n, col)

func _flat_poly(poly: PackedVector2Array, h: float, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var st := _tool(poly[0])
	for i in range(0, tris.size(), 3):
		_tri(st, _v(poly[tris[i]], h), _v(poly[tris[i + 1]], h), _v(poly[tris[i + 2]], h), Vector3.UP, col)

func _area(area: Dictionary) -> void:
	if AREA_COL.has(area["kind"]):
		_flat_poly(_open(area["poly"]), 0.005, AREA_COL[area["kind"]])

## A road: its sidewalk band, the carriageway, and a centre line on arterials.
func _road(r: Dictionary) -> void:
	var w: float = r.get("w", ROAD_W.get(r["tier"], 6.0))
	var walk: float = r.get("walk", 0.0)
	if walk > 0.0:
		_ribbon(r["pts"], w * 0.5 + walk, 0.02, SIDEWALK)
	_ribbon(r["pts"], w * 0.5, 0.04, ROAD_COL.get(r["tier"], ROAD_COL["res"]))
	if r["tier"] == "art":
		_ribbon(r["pts"], 0.1, 0.05, CENTRE_LINE)

## A ribbon along a polyline, with a square under each joint so bends close.
func _ribbon(pts: PackedVector2Array, half: float, h: float, col: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := (b - a).orthogonal().normalized() * half
		_quad(_tool(a), [_v(a + n, h), _v(b + n, h), _v(b - n, h), _v(a - n, h)], Vector3.UP, col)
		if i > 0:
			var s := Vector2(half, half)
			_quad(_tool(a), [_v(a - s, h - 0.001), _v(a + Vector2(s.x, -s.y), h - 0.001), _v(a + s, h - 0.001), _v(a + Vector2(-s.x, s.y), h - 0.001)], Vector3.UP, col)

static func _open(poly: PackedVector2Array) -> PackedVector2Array:
	return poly.slice(0, poly.size() - 1) if poly.size() > 3 and poly[0] == poly[poly.size() - 1] else poly

static func _ccw(poly: PackedVector2Array) -> bool:
	var area := 0.0
	for i in poly.size():
		area += poly[i].x * poly[(i + 1) % poly.size()].y - poly[(i + 1) % poly.size()].x * poly[i].y
	return area > 0.0

## A building: walls, a roof, windows per storey, and its door set in the wall it faces.
func _building(b: Dictionary) -> void:
	var poly := _open(b["poly"])
	if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return
	var levels: int = maxi(1, int(b.get("levels", 1)))
	var h := levels * STOREY_M
	var col: Color = WALLS.get(b["kind"], WALLS["building"]).lightened(absi(String(b["id"]).hash() % 7) * 0.012)
	var st := _tool(poly[0])
	var ccw := _ccw(poly)
	var door_edge := _door_edge(poly, b.get("door", Vector2.INF))
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var e := c - a
		if e.length() < 0.05:
			continue
		var out := (Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)).normalized()
		var n := Vector3(out.x, 0, out.y)
		_quad(st, [_v(a), _v(c), _v(c, h), _v(a, h)], n, col)
		var door_t := _door_t(a, c, b["door"]) if i == door_edge else -1.0
		_openings(st, a, c, out, levels, door_t)
	_flat_poly(poly, h, col.darkened(0.25).lerp(ROOF, 0.4))

## Windows every ~3 m per storey, set just proud of the wall; on the ground
## floor of the door's wall the window nearest the door gives way to the door.
func _openings(st: SurfaceTool, a: Vector2, c: Vector2, out: Vector2, levels: int, door_t: float) -> void:
	var length := a.distance_to(c)
	var dir := (c - a) / length
	var n := Vector3(out.x, 0, out.y)
	var proud := out * 0.04
	if door_t >= 0.0:
		var mid := a.lerp(c, door_t) + proud
		var half := dir * DOOR_W * 0.5
		_quad(st, [_v(mid - half * 1.25, 0.0), _v(mid + half * 1.25, 0.0), _v(mid + half * 1.25, DOOR_H + 0.15), _v(mid - half * 1.25, DOOR_H + 0.15)], n, DOOR_FRAME)
		var inner := mid + proud * 0.5
		_quad(st, [_v(inner - half, 0.0), _v(inner + half, 0.0), _v(inner + half, DOOR_H), _v(inner - half, DOOR_H)], n, DOOR)
	var count := int(length / 3.0)
	for lv in levels:
		for k in count:
			var t := (k + 0.5) / count
			if lv == 0 and door_t >= 0.0 and absf(t - door_t) * length < 1.6:
				continue
			var p := a.lerp(c, t) + proud
			var w := dir * 0.55
			var y := lv * STOREY_M + 1.0
			_quad(st, [_v(p - w, y), _v(p + w, y), _v(p + w, y + 1.2), _v(p - w, y + 1.2)], n, GLASS)

## The wall closest to the door point (the door sits just outside it).
static func _door_edge(poly: PackedVector2Array, door: Vector2) -> int:
	if door == Vector2.INF:
		return -1
	var best := -1
	var best_d := INF
	for i in poly.size():
		var p := Geometry2D.get_closest_point_to_segment(door, poly[i], poly[(i + 1) % poly.size()])
		var d := p.distance_squared_to(door)
		if d < best_d:
			best_d = d
			best = i
	return best

## Where along wall a->c the door sits (0..1), kept a door's width from the corners.
static func _door_t(a: Vector2, c: Vector2, door: Vector2) -> float:
	var length := a.distance_to(c)
	if length < DOOR_W * 1.6:
		return -1.0
	var t := clampf((door - a).dot(c - a) / (length * length), 0.0, 1.0)
	var margin := DOOR_W / length
	return clampf(t, margin, 1.0 - margin)

func _commit() -> Array[Node3D]:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var out: Array[Node3D] = []
	for k in _tools:
		var mi := MeshInstance3D.new()
		mi.mesh = _tools[k].commit()
		mi.material_override = mat
		mi.name = "Chunk_%d_%d" % [k.x, k.y]
		out.append(mi)
	return out

## LA palms: a tall trunk and a crown of drooping fronds, two MultiMeshes.
func _palms(wells: PackedVector2Array) -> Array[Node3D]:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.26
	trunk.height = 9.0
	trunk.radial_segments = 6
	var crown := _fronds()
	var out: Array[Node3D] = []
	for part in [[trunk, Color("7a5f45"), 4.5], [crown, Color("4f7a3a"), 9.0]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = wells.size()
		for i in wells.size():
			var turn := Basis(Vector3.UP, float(absi(int(wells[i].x * 7.0 + wells[i].y * 13.0)) % 360) * PI / 180.0)
			mm.set_instance_transform(i, Transform3D(turn, _v(wells[i], part[2])))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[1]
		mat.roughness = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mmi.material_override = mat
		out.append(mmi)
	return out

## Eight long leaves round the top, each bending down at the tip.
static func _fronds() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0)
		var side := d.orthogonal() * 0.35
		var p0 := Vector3(0, 0.2, 0)
		var p1 := Vector3(d.x * 1.6, 0.5, d.y * 1.6)
		var p2 := Vector3(d.x * 3.0, -0.6, d.y * 3.0)
		var s := Vector3(side.x, 0, side.y)
		for tri in [[p0, p1 + s, p1 - s], [p1 + s, p2, p1 - s]]:
			st.set_normal(Vector3.UP)
			for v in tri:
				st.add_vertex(v)
	return st.commit()
