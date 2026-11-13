## R3D0: a look test for the 3D city: one block of the real map around the
## spawn, built in true 3D and seen through Zomboid's fixed isometric camera
## (orthographic, 45 degrees round, 30 down). Buildings are raised from their
## real footprints (walls, roof, a row of windows per storey, the door);
## roads and sidewalks lie on the ground; palms stand in the tree wells;
## people are box figures. No shadows (standing rule). Not wired into the
## game yet: it only reads CityData, the same data the 2D map draws.
extends Node3D

const RADIUS_M := 110.0
const STOREY_M := 3.2
const ROAD_W := {"fwy": 26.0, "ramp": 6.0, "art": 14.0, "res": 6.0, "alley": 3.0, "path": 2.5, "svc": 7.0, "hill": 5.0, "trail": 2.5, "aisle": 7.3, "drive": 3.7}
const WALLS := {"house": Color("d9c7a8"), "apartments": Color("cdb48f"), "commercial": Color("c9b9a4"), "industrial": Color("b4b8bc"),
	"garage": Color("d8d2c4"), "civic": Color("c7a98f"), "building": Color("cfc3ad")}
const ROOF := Color("8a7f72")
const GROUND := Color("e9e1cf")
const ASPHALT := Color("6f6e6a")
const SIDEWALK := Color("c9c5bc")
const GLASS := Color("3b4a5c")
const DOOR := Color("3a2a1e")

var centre := Vector2.ZERO
var camera := Camera3D.new()

func _ready() -> void:
	var city := CityData.load_file()
	centre = city.spawn
	_environment()
	_ground()
	for r in city.roads:
		if _near_pts(r["pts"]):
			_road(r)
	for b in city.buildings:
		if _near_pts(b["poly"]):
			_building(b)
	for w in city.tree_wells:
		if w.distance_to(centre) < RADIUS_M:
			_palm(w)
	_person(centre, Color(0.1, 0.85, 0.3))
	for k in 6:
		_person(centre + Vector2.from_angle(k * 1.1) * (8.0 + k * 3.0), Color(0.36, 0.38, 0.45))
	_camera()

func _near_pts(pts: PackedVector2Array) -> bool:
	for p in pts:
		if p.distance_to(centre) < RADIUS_M:
			return true
	return false

## 2D map metres -> 3D (x east, y up, z south), centred on the block.
func _v(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x - centre.x, h, p.y - centre.y)

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	return m

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)   # afternoon sun from the south-west: walls read by shade, no shadows cast
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)

func _ground() -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * RADIUS_M * 3.0
	plane.mesh = pm
	plane.material_override = _mat(GROUND)
	add_child(plane)

## A road as a flat ribbon on its centreline, with its sidewalk under it.
func _road(r: Dictionary) -> void:
	var w: float = r.get("w", ROAD_W.get(r["tier"], 6.0))
	var walk: float = r.get("walk", 0.0)
	if walk > 0.0:
		_ribbon(r["pts"], w * 0.5 + walk, 0.02, SIDEWALK)
	_ribbon(r["pts"], w * 0.5, 0.04, ASPHALT)
	if r["tier"] == "art":
		_ribbon(r["pts"], 0.12, 0.05, Color("d8b23e"))   # the centre line

func _ribbon(pts: PackedVector2Array, half: float, h: float, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := (b - a).orthogonal().normalized() * half
		var q := [_v(a + n, h), _v(b + n, h), _v(b - n, h), _v(a - n, h)]
		for t in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[t])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(col)
	add_child(mi)

## A building raised from its footprint: walls, flat roof, windows, the door.
func _building(b: Dictionary) -> void:
	var poly: PackedVector2Array = b["poly"]
	if poly.size() > 3 and poly[0] == poly[poly.size() - 1]:
		poly = poly.slice(0, poly.size() - 1)
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var levels: int = maxi(1, int(b.get("levels", 1)))
	var h := levels * STOREY_M
	var wall_col: Color = WALLS.get(b["kind"], WALLS["building"]).lightened((String(b["id"]).hash() % 7) * 0.012)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ccw := _ccw(poly)
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var e := c - a
		var out := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
		st.set_normal(Vector3(out.x, 0, out.y).normalized())
		var q := [_v(a), _v(c), _v(c, h), _v(a, h)]
		for t in [0, 2, 1, 0, 3, 2] if ccw else [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[t])
		_windows(a, c, out.normalized(), levels)
	var walls := MeshInstance3D.new()
	walls.mesh = st.commit()
	walls.material_override = _mat(wall_col)
	walls.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(walls)
	var rt := SurfaceTool.new()
	rt.begin(Mesh.PRIMITIVE_TRIANGLES)
	rt.set_normal(Vector3.UP)
	for k in tris:
		rt.add_vertex(_v(poly[k], h))
	var roof := MeshInstance3D.new()
	roof.mesh = rt.commit()
	roof.material_override = _mat(wall_col.darkened(0.25).lerp(ROOF, 0.4))
	roof.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(roof)
	if b.has("door"):
		_box(b["door"], Vector3(1.2, 2.1, 0.15), 0.0, DOOR)

## One window every ~3 m along a wall, per storey, set just proud of it.
func _windows(a: Vector2, c: Vector2, out: Vector2, levels: int) -> void:
	var length := a.distance_to(c)
	var count := int(length / 3.0)
	if count < 1:
		return
	for lv in levels:
		for k in count:
			var p := a.lerp(c, (k + 0.5) / count) + out * 0.06
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.1, 1.2, 0.08)
			box.mesh = bm
			box.material_override = _mat(GLASS)
			box.position = _v(p, lv * STOREY_M + 1.6)
			box.rotation.y = -atan2(c.y - a.y, c.x - a.x)
			add_child(box)

func _ccw(poly: PackedVector2Array) -> bool:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return area > 0.0

func _box(at: Vector2, size: Vector3, h: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = _v(at, h + size.y * 0.5)
	add_child(mi)
	return mi

## An LA palm: a tall thin trunk and a flat green crown.
func _palm(at: Vector2) -> void:
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.28
	cm.height = 9.0
	trunk.mesh = cm
	trunk.material_override = _mat(Color("7a5f45"))
	trunk.position = _v(at, 4.5)
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 1.4
	crown.mesh = sm
	crown.material_override = _mat(Color("4f7a3a"))
	crown.position = _v(at, 9.2)
	add_child(crown)

## A person as boxes: legs, torso, head (the same box people, now standing in 3D).
func _person(at: Vector2, col: Color) -> void:
	_box(at, Vector3(0.45, 0.85, 0.3), 0.0, Color(0.16, 0.17, 0.22))
	_box(at, Vector3(0.55, 0.7, 0.32), 0.85, col)
	_box(at, Vector3(0.3, 0.3, 0.3), 1.55, col.lightened(0.35))

## Zomboid's camera: orthographic, turned 45 degrees, looking 30 degrees down.
func _camera() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 70.0
	camera.rotation_degrees = Vector3(-30, 45, 0)
	camera.position = Vector3(60, 60, 60)
	camera.near = 0.1
	camera.far = 500.0
	add_child(camera)
	camera.current = true
