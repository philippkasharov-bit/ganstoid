## R3D1: the whole district in 3D, built once and fast to draw. The map is
## cut into CHUNK_M squares; each square becomes ONE mesh (ground areas,
## sidewalks, roads, every building's walls, roof, windows and door) coloured
## per vertex (buildings styled by BuildingMesh3D), so thousands of buildings
## cost a few dozen draw calls and the
## camera culls the squares it cannot see. OPT1: CityStream3D builds one
## chunk at a time (`only`), from that chunk's slice of the data; geometry an
## item puts in a neighbour's square is dropped (the neighbour draws it).
## Reads CityData only; the simulation never sees this.
## Map (x, y) -> 3D (x, height, y), relative to `origin`.
class_name CityMesh3D
extends RefCounted

const CHUNK_M := 160.0
const ROAD_W := {"fwy": 26.0, "ramp": 6.0, "art": 14.0, "res": 6.0, "alley": 3.0, "path": 2.5, "svc": 7.0, "hill": 5.0, "trail": 2.5, "aisle": 7.3, "drive": 3.7}
const ASPHALT := Color("777671")   # B1: one asphalt for every driven road, so overlaps at junctions do not show
const ROAD_COL := {"fwy": ASPHALT, "ramp": ASPHALT, "art": ASPHALT, "res": ASPHALT, "alley": ASPHALT,
	"path": Color("cfcbc1"), "svc": ASPHALT, "hill": Color("8f8570"), "trail": Color("9b8357"), "aisle": ASPHALT, "drive": Color("b8b4aa")}
const AREA_COL := {"park": Color("a9c48f"), "hills": Color("d6dcc4"), "mountains": Color("b9c6a8"), "airfield": Color("dcd8cc"),
	"foothill": Color("e3dac6"), "industrial": Color("d3cfd8"), "downtown": Color("d8cbb0"), "commercial": Color("e1d4ba"), "river": Color("9fb3bf")}
const SIDEWALK := Color("cbc7be")
const CENTRE_LINE := Color("d8b23e")
const ROAD_SURFACE := {"path": SurfaceDetail.SIDEWALK, "drive": SurfaceDetail.SIDEWALK, "hill": SurfaceDetail.DIRT, "trail": SurfaceDetail.DIRT}   # TX1: the rest is asphalt

const ALL := Vector2i(-1000000, -1000000)

var origin := Vector2.ZERO
var only := ALL    # OPT1: the one chunk being built (ALL: every chunk)
var _tools := {}   # chunk Vector2i -> SurfaceTool
var _decals := {}  # B2: chunk Vector2i -> graffiti SurfaceTool
var space: RoadSpace     # B1: where other roads cross (the centre line stops there)
var _sink: SurfaceTool   # geometry for other chunks lands here and is thrown away

## Every chunk mesh plus the palms, as nodes ready to add under a Node3D.
static func build(city: CityData, centre: Vector2, radius: float, at_origin: Vector2 = Vector2.INF, chunk: Vector2i = ALL, keep: Rect2 = Rect2(), real: CityReal = null) -> Array[Node3D]:
	var b := CityMesh3D.new()
	b.origin = centre if at_origin == Vector2.INF else at_origin
	b.only = chunk
	var r2 := radius * radius
	for area in city.areas:
		if _near(area["poly"], centre, r2):
			b._area(area)
	b.space = RoadSpace.of(city)
	for i in city.roads.size():
		if _near(city.roads[i]["pts"], centre, r2):
			b._road(city.roads[i], i)
	for i in city.buildings.size():
		if _near(city.buildings[i]["poly"], centre, r2):
			b._building(city.buildings[i], city.buildings[i].get("tag", i + 1))   # R3D7: its tag is its city index + 1 (0: not a building)
			Graffiti3D.on_building(b, city.buildings[i], city.buildings[i].get("tag", i + 1))   # B2
	if real == null:
		real = CityReal.load_files()
	CityDetail3D.add(b, city, real, centre, radius)   # D2: yards, lots, pools, walls, fences, crossings, hydrants
	var out: Array[Node3D] = b._commit()
	out.append_array(CityProps3D.build(city, real, centre, radius, b.origin, keep))   # D2: shade trees, power lines
	var wells := PackedVector2Array()
	for w in city.tree_wells:
		if w.distance_squared_to(centre) < r2 and (not keep.has_area() or keep.has_point(w)):
			wells.append(b.space.clear(w, 0.8))   # B1: no palm in the lane
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
	if only != ALL and k != only:
		if _sink == null:
			_sink = SurfaceTool.new()
			_sink.begin(Mesh.PRIMITIVE_TRIANGLES)
			_sink.set_uv(Vector2.ZERO)   # same vertex format as a chunk (without it, every UV set logs an error)
		return _sink
	if not _tools.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_uv(Vector2.ZERO)    # R3D7: UV.y carries each building's tag for the Cutaway; 0 = not a building
		_tools[k] = st
	return _tools[k]

## B2: the chunk's graffiti mesh (its own material: the tag atlas, cut out).
func decal_tool(at: Vector2) -> SurfaceTool:
	var k := Vector2i(((at - origin) / CHUNK_M).floor())
	if only != ALL and k != only:
		return null
	if not _decals.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_uv(Vector2.ZERO)
		st.set_uv2(Vector2.ZERO)
		_decals[k] = st
	return _decals[k]

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
		var col: Color = AREA_COL[area["kind"]]
		_flat_poly(_open(area["poly"]), 0.005, SurfaceDetail.mark(col, SurfaceDetail.GRASS) if area["kind"] == "park" else col)

## A road: its sidewalk band, the carriageway, and a centre line on arterials.
func _road(r: Dictionary, own: int) -> void:
	var w: float = r.get("w", ROAD_W.get(r["tier"], 6.0))
	var walk: float = r.get("walk", 0.0)
	if walk > 0.0:
		_ribbon(r["pts"], w * 0.5 + walk, 0.02, SurfaceDetail.mark(SIDEWALK, SurfaceDetail.SIDEWALK))
	var h := 0.04 if ROAD_SURFACE.get(r["tier"], SurfaceDetail.ASPHALT) == SurfaceDetail.ASPHALT else 0.035   # B1: paths and driveways tuck under the asphalt, no z-fight
	_ribbon(r["pts"], w * 0.5, h, SurfaceDetail.mark(ROAD_COL.get(r["tier"], ROAD_COL["res"]), ROAD_SURFACE.get(r["tier"], SurfaceDetail.ASPHALT)))
	if r["tier"] == "art":
		_centre_line(r["pts"], own)

## B1: the double-yellow, in 2 m pieces, left out where another road crosses.
func _centre_line(pts: PackedVector2Array, own: int) -> void:
	for i in pts.size() - 1:
		var length := pts[i].distance_to(pts[i + 1])
		var pieces := maxi(1, ceili(length / 2.0))
		for k in pieces:
			var a := pts[i].lerp(pts[i + 1], float(k) / pieces)
			var b := pts[i].lerp(pts[i + 1], float(k + 1) / pieces)
			if space == null or not space.inside((a + b) * 0.5, 0.3, own):
				_ribbon(PackedVector2Array([a, b]), 0.1, 0.05, CENTRE_LINE)

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

## A building, styled by BuildingMesh3D (R3D2: each one rolls its own look).
func _building(b: Dictionary, tag: int) -> void:
	var poly: PackedVector2Array = b["poly"]
	BuildingMesh3D.add(_tool(poly[0]), b, _v, tag)

func _commit() -> Array[Node3D]:
	var mat := Cutaway.shared("city")   # R3D4: see-through where it hides the player
	var out: Array[Node3D] = []
	for k in _tools:
		var mi := MeshInstance3D.new()
		mi.mesh = _tools[k].commit()
		mi.material_override = mat
		mi.name = "Chunk_%d_%d" % [k.x, k.y]
		out.append(mi)
	for k in _decals:
		var tags := MeshInstance3D.new()
		tags.mesh = _decals[k].commit()
		tags.material_override = Graffiti3D.material()
		tags.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(tags)
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
		mmi.material_override = Cutaway.shared("palm_%s" % part[2], part[1], false, 1.0, 0.0, 1.0)   # D2: palms sway
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
