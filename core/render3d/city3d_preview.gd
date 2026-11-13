## R3D0/R3D1: a look test for the 3D city: the real map around the spawn,
## built by CityMesh3D (chunked meshes, doors set in their walls, palms) and
## seen through Zomboid's fixed isometric camera (orthographic, 45 degrees
## round, 30 down). People are box figures. No shadows (standing rule).
## R3D3: with live_sim the real simulation runs under it (a WorldDriver) and
## RenderSync3D stands its people and cars in the city. Not the game's main
## view yet.
extends Node3D

const RADIUS_M := 110.0
const GROUND := Color("e9e1cf")

var centre := Vector2.ZERO
var rig := CameraRig3D.new()
var day_night := DayNight3D.new()   # R3D10: sun, sky, lamps by the game clock
var env: Environment
var sun: DirectionalLight3D   # R3D6: follows the player, zooms, turns

@export var radius_m := RADIUS_M
@export var live_sim := false
var build_ms := 0.0
var driver: Node
var city_data: CityData
var people3d: RenderSync3D

func _ready() -> void:
	var city := CityData.load_file()
	city_data = city
	centre = city.spawn
	_environment()
	var t0 := Time.get_ticks_msec()
	for n in CityMesh3D.build(city, centre, radius_m):   # R3D1: chunked meshes + palm MultiMeshes
		add_child(n)
	build_ms = Time.get_ticks_msec() - t0
	_ground()
	if live_sim:
		_run_sim()
	else:
		_person(centre, Color(0.1, 0.85, 0.3))
		for k in 6:
			_person(centre + Vector2.from_angle(k * 1.1) * (8.0 + k * 3.0), Color(0.36, 0.38, 0.45))
	rig.origin = centre
	day_night.origin = centre
	day_night.world = driver.world if driver != null else null
	day_night.sun = sun
	day_night.city = city_data
	day_night.radius = radius_m + 60.0
	day_night.env = env
	add_child(day_night)
	rig.world = driver.world if driver != null else null
	add_child(rig)

## R3D3: the real sim (no new-game panel) with its people drawn in 3D.
func _run_sim() -> void:
	Engine.set_meta("skip_new_game", true)
	driver = load("res://core/world_driver.gd").new()
	add_child(driver)
	people3d = RenderSync3D.new()
	people3d.world = driver.world
	people3d.origin = centre
	people3d.footprints = Footprints.build(city_data, centre, radius_m + 40.0)
	add_child(people3d)
	var aim := AimView3D.new()   # R3D12: the mouse aims and clicks in 3D
	aim.world = driver.world
	aim.origin = centre
	add_child(aim)

## 2D map metres -> 3D (x east, y up, z south), centred on the block.
func _v(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x - centre.x, h, p.y - centre.y)

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	return m

func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)   # afternoon sun from the south-west: walls read by shade, no shadows cast
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)

func _ground() -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * radius_m * 2.5
	plane.mesh = pm
	plane.position.y = -0.01
	plane.material_override = Cutaway.material(GROUND, false, 1.0)   # R3D8: darkens outside your view too
	add_child(plane)

func _box(at: Vector2, size: Vector3, h: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = _v(at, h + size.y * 0.5)
	add_child(mi)
	return mi

## A person as boxes: legs, torso, head (the same box people, now standing in 3D).
func _person(at: Vector2, col: Color) -> void:
	_box(at, Vector3(0.45, 0.85, 0.3), 0.0, Color(0.16, 0.17, 0.22))
	_box(at, Vector3(0.55, 0.7, 0.32), 0.85, col)
	_box(at, Vector3(0.3, 0.3, 0.3), 1.55, col.lightened(0.35))
