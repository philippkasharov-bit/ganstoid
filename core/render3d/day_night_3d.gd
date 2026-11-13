## R3D10: day and night in 3D, by the game clock. The sun warms at dawn and
## dusk and the sky goes dark; at night the city is dark except under its
## street lamps (warm pools), in lit windows and shop fronts, and in the
## headlights of moving cars. The Cutaway shader does the darkening, so what
## you can see at night is what is lit; light_at() gives the same light for
## people and cars, which are tinted to match. Lamps come from StreetLights
## (the sim's own layout: witnesses see by the same light); posts are drawn
## as a MultiMesh.
class_name DayNight3D
extends Node

const POST_H := 5.5
const LAMP_REACH := 100.0       # lamps this near the player light the scene
const MAX_LIGHTS := 96          # the shader's list
const HEADLIGHT_AHEAD := 6.0
const HEADLIGHT_R := 7.0
const SKY_DAY := Color("e9e1cf")
const SKY_NIGHT := Color("0d1018")
const SUN_DAY := Color(1.0, 0.98, 0.94)
const SUN_LOW := Color(1.0, 0.72, 0.5)

static var night := 0.0         # 0 full day .. 1 full night
static var _near: PackedVector3Array = PackedVector3Array()   # x, y map; z radius: lights round the player now

var world: World
var origin := Vector2.ZERO
var sun: DirectionalLight3D
var env: Environment
var hour_override := -1.0       # checks and screenshots: a fixed hour
var city: CityData              # streets to light (set by the view)
var radius := 300.0             # lamps placed this far round origin
var _lights: StreetLights

func _ready() -> void:
	_lights = StreetLights.build(city, origin, radius)   # the same layout the sim sees by
	add_child(_posts(_lights.lamps))

## Posts as tall as their pool is wide, each with a head that glows at night.
func _posts(at: PackedVector3Array) -> Node3D:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.08
	pole.bottom_radius = 0.09
	pole.height = 1.0
	pole.radial_segments = 5
	var head := BoxMesh.new()
	head.size = Vector3(0.7, 0.18, 0.35)
	var both := Node3D.new()
	var posts := _multi(pole, Cutaway.material(Color("4a4d52"), false, 0.8))
	var heads := _multi(head, Cutaway.material(Color("ffe2a8"), false, 0.6, 1.4))   # cut with its pole; glows at night
	for mi in [posts, heads]:
		mi.multimesh.instance_count = at.size()
		both.add_child(mi)
	for i in at.size():
		var tall := POST_H * at[i].z / 11.0
		var foot := Vector3(at[i].x - origin.x, 0, at[i].y - origin.y)
		posts.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, tall, 1)), foot + Vector3(0, tall * 0.5, 0)))
		heads.multimesh.set_instance_transform(i, Transform3D(Basis(), foot + Vector3(0, tall - 0.05, 0)))
	return both

static func _multi(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _process(_delta: float) -> void:
	if world == null and hour_override < 0.0:
		return
	var hour := hour_override if hour_override >= 0.0 else SimClock.day_fraction(world.tick) * 24.0
	night = StreetLights.darkness(hour)
	_sky(hour)
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	_gather((player.get_component(ComponentNames.NPC) as NPCData).position if player != null else origin)
	var list := PackedVector4Array()
	for l in _near:
		list.append(Vector4(l.x - origin.x, l.y - origin.y, l.z, 1.0))
	Cutaway.light(night, list)

func _sky(hour: float) -> void:
	var golden := maxf(1.0 - absf(hour - 6.5) / 1.2, 1.0 - absf(hour - 19.0) / 1.2)   # warm only round sunrise and sunset
	if sun != null:
		sun.light_color = SUN_DAY.lerp(SUN_LOW, clampf(golden, 0.0, 1.0))
		sun.light_energy = lerpf(0.9, 0.55, night)   # the shader does the dark; the sun only cools
	if env != null:
		env.background_color = SKY_DAY.lerp(SKY_NIGHT, night)
		env.ambient_light_color = Color(0.85, 0.85, 0.9).lerp(Color(0.55, 0.62, 0.85), night)
		env.ambient_light_energy = lerpf(0.75, 0.55, night)   # day: shaded walls stay readable
	if sun != null:
		sun.light_color = sun.light_color.lerp(Color(0.6, 0.68, 0.95), night)   # moonlight blue

## The lamps and headlights near `p`, nearest first, at most MAX_LIGHTS.
func _gather(p: Vector2) -> void:
	var found: Array = []
	for l in _lights.near(p, LAMP_REACH):
		found.append(l)
	for id in (world.get_entities_with_component(ComponentNames.VEHICLE) if world != null else {}):
		var car: VehicleData = world.entities[id].get_component(ComponentNames.VEHICLE)
		if car.driver_id != &"" and car.position.distance_to(p) < LAMP_REACH:
			var ahead := car.position + Vector2.from_angle(car.heading) * HEADLIGHT_AHEAD
			found.append(Vector3(ahead.x, ahead.y, HEADLIGHT_R))
	found.sort_custom(func(a: Vector3, b: Vector3) -> bool: return Vector2(a.x, a.y).distance_squared_to(p) < Vector2(b.x, b.y).distance_squared_to(p))
	_near = PackedVector3Array(found.slice(0, MAX_LIGHTS))

## How lit map point `p` is now: 1 by day; at night moonlight plus any lamp pool.
static func light_at(p: Vector2) -> float:
	var lamp := 0.0
	for l in _near:
		var d := Vector2(l.x, l.y).distance_to(p)
		lamp += StreetLights.pool(d, l.z)
	return lerpf(1.0, maxf(StreetLights.MOON, minf(1.0, lamp)), night)
