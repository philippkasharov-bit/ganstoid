## R3D13: the game's 3D view (Zomboid's: orthographic, 45 degrees round, 30
## down). Builds the district in 3D round the spawn and puts the sim in it:
## people and cars (RenderSync3D), aim and clicks (AimView3D), day and night
## (DayNight3D), the camera (CameraRig3D). In the main scene it replaces the
## 2D map; F9 flips back to the 2D map (its overlays are not all in 3D yet).
## No shadows (standing rule).
class_name GameView3D
extends Node3D

const GROUND := Color("e9e1cf")
const MAP_2D := ["CityLayer", "RenderSync", "StreetFurniture", "TurfOverlay", "AimView", "Camera2D"]

@export var world_driver_path: NodePath
@export var radius_m := 900.0   # the simulated district

var world: World
var city_data: CityData
var centre := Vector2.ZERO
var rig := CameraRig3D.new()
var day_night := DayNight3D.new()
var people3d := RenderSync3D.new()
var aim := AimView3D.new()
var furniture := StreetFurniture3D.new()
var stream := CityStream3D.new()
var turf_map := TurfMap3D.new()   # T3: U in 3D   # OPT1: builds the city round you, drops it behind you
var _plane: MeshInstance3D
const CITY_M := 9000.0   # signals, stop signs, bus stops
var env: Environment
var sun: DirectionalLight3D
var build_ms := 0.0
var on := true

func _ready() -> void:
	if world_driver_path.is_empty():
		return   # set up by hand (the preview)
	var driver := get_node(world_driver_path)
	setup(driver.world, driver.city, driver.city.spawn)
	show_3d.call_deferred(true)

## Build the city round `at` and hang the sim's views on it.
func setup(w: World, city: CityData, at: Vector2) -> void:
	world = w
	city_data = city
	centre = at
	Cutaway.reset()
	Cutaway.shared("city")   # TX1: made here, not on a stream worker (its detail textures load once)
	_environment()
	_ground()
	day_night.origin = centre
	day_night.city = city
	day_night.radius = CITY_M   # lamps everywhere the stream can go
	var t0 := Time.get_ticks_msec()
	stream.setup(city, centre, day_night.layout())   # OPT1: only the city round you is built
	add_child(stream)
	stream.prime(_player_at(at))
	build_ms = Time.get_ticks_msec() - t0
	people3d.world = world
	people3d.origin = centre
	people3d.footprints = Footprints.build(city, centre, CITY_M)
	add_child(people3d)
	aim.world = world
	aim.origin = centre
	add_child(aim)
	furniture.world = world
	furniture.origin = centre
	add_child(furniture)
	turf_map.world = world
	turf_map.origin = centre
	turf_map.visible = false
	add_child(turf_map)
	day_night.world = world
	day_night.sun = sun
	day_night.env = env
	add_child(day_night)
	rig.origin = centre
	rig.world = world
	rig.follow = people3d
	add_child(rig)

## Switch between the 3D view and the old 2D map.
func show_3d(yes: bool) -> void:
	on = yes
	visible = yes
	for n in [rig, people3d, aim, day_night, furniture, stream]:
		n.process_mode = Node.PROCESS_MODE_INHERIT if yes else Node.PROCESS_MODE_DISABLED
	rig.camera.current = yes
	ScreenMap.use_3d(rig.camera if yes else null, centre)
	for name in MAP_2D:
		var n := get_parent().get_node_or_null(name)
		if n != null:
			n.visible = not yes if n is CanvasItem else true
			n.process_mode = Node.PROCESS_MODE_DISABLED if yes else Node.PROCESS_MODE_INHERIT
	var cam2d := get_parent().get_node_or_null("Camera2D") as Camera2D
	if cam2d != null and not yes:
		cam2d.make_current()

## U in 3D opens the map view (2D map with the turf / money overlay); when
## the overlay is cycled off again, back to 3D.
func _process(_delta: float) -> void:
	_follow()
	if on and InputMap.has_action(&"turf_map") and Input.is_action_just_pressed(&"turf_map"):
		turf_map.cycle()   # T3: turf, money, off, laid over the 3D city

func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		show_3d(not on)

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
	sun.rotation_degrees = Vector3(-55, -35, 0)   # afternoon sun from the south-west: walls read by shade
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)

## OPT1: the stream and the ground go where the player is.
func _follow() -> void:
	var at := people3d.player_shown
	if at == Vector2.INF:
		return
	stream.focus = at
	turf_map.focus = at
	_plane.position = Vector3(roundf(at.x - centre.x), -0.01, roundf(at.y - centre.y))

func _player_at(fallback: Vector2) -> Vector2:
	var p: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	return (p.get_component(ComponentNames.NPC) as NPCData).position if p != null else fallback

func _ground() -> void:
	var plane := MeshInstance3D.new()
	_plane = plane
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * (CityStream3D.UNLOAD_M * 2.5)   # follows you: only as big as what is built
	plane.mesh = pm
	plane.position.y = -0.01
	plane.material_override = Cutaway.material(GROUND, false, 1.0)   # darkens outside your view too
	add_child(plane)
