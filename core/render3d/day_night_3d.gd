## R3D10: day and night in 3D, by the game clock. The sun warms at dawn and
## dusk and the sky goes dark; at night the city is dark except under its
## street lamps (warm pools), in lit windows and shop fronts, and in the
## headlights of moving cars. The Cutaway shader does the darkening, so what
## you can see at night is what is lit; light_at() gives the same light for
## people and cars, which are tinted to match. The map's own lamps are few,
## so streets also get a lamp every LAMP_EVERY metres, alternating sides
## (posts drawn as a MultiMesh).
class_name DayNight3D
extends Node

const LAMP_R := 10.0
const LAMP_EVERY := 30.0
const LAMP_ROADS := ["art", "res", "svc"]
const POST_H := 5.5
const LAMP_REACH := 110.0       # lamps this near the player light the scene
const MAX_LIGHTS := 64          # the shader's list
const HEADLIGHT_AHEAD := 6.0
const HEADLIGHT_R := 7.0
const MOON := 0.28              # how much an unlit street shows at deep night
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
var _lamps: Dictionary = {}     # Vector2i (40 m cell) -> PackedVector2Array

func _ready() -> void:
	var all := PackedVector2Array()
	for p in CityReal.load_files().points:
		if p["kind"] == "lamp" and p["p"].distance_to(origin) < radius:
			all.append(p["p"])
	if city != null:
		all.append_array(_street_lamps())
	for l in all:
		var key := Vector2i((l / 40.0).floor())
		if not _lamps.has(key):
			_lamps[key] = PackedVector2Array()
		_lamps[key].append(l)
	add_child(_posts(all))

## A lamp every LAMP_EVERY metres along lit streets, at the kerb, sides alternating.
func _street_lamps() -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in city.roads:
		if not r["tier"] in LAMP_ROADS or r["pts"][0].distance_to(origin) > radius:
			continue
		var pts: PackedVector2Array = r["pts"]
		var off: float = float(r.get("w", 6.0)) * 0.5 + 0.7
		var run := LAMP_EVERY * 0.5
		var side := 1.0
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			var length := seg.length()
			while run < length and length > 0.0:
				out.append(pts[i] + seg * (run / length) + seg.normalized().orthogonal() * off * side)
				side = -side
				run += LAMP_EVERY
			run -= length
	return out

func _posts(at: PackedVector2Array) -> MultiMeshInstance3D:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = POST_H
	pole.radial_segments = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pole
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(at[i].x - origin.x, POST_H * 0.5, at[i].y - origin.y)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = Cutaway.material(Color("4a4d52"), false, 0.8)
	return mi

func _process(_delta: float) -> void:
	if world == null and hour_override < 0.0:
		return
	var hour := hour_override if hour_override >= 0.0 else SimClock.day_fraction(world.tick) * 24.0
	night = darkness(hour)
	_sky(hour)
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	_gather((player.get_component(ComponentNames.NPC) as NPCData).position if player != null else origin)
	var list := PackedVector4Array()
	for l in _near:
		list.append(Vector4(l.x - origin.x, l.y - origin.y, l.z, 1.0))
	Cutaway.light(night, list)

## 0 by day, 1 at night, easing through dusk (18:00-20:30) and dawn (5:00-7:00).
static func darkness(hour: float) -> float:
	if hour >= 7.0 and hour <= 18.0:
		return 0.0
	if hour > 18.0:
		return smoothstep(18.0, 20.5, hour)
	return 1.0 - smoothstep(5.0, 7.0, hour)

func _sky(hour: float) -> void:
	var low := 1.0 - absf(hour - 12.5) / 6.5   # 1 at midday, 0 at sunrise/sunset
	if sun != null:
		sun.light_color = SUN_LOW.lerp(SUN_DAY, clampf(low * 2.0, 0.0, 1.0))
		sun.light_energy = lerpf(0.9, 0.55, night)   # the shader does the dark; the sun only cools
	if env != null:
		env.background_color = SKY_DAY.lerp(SKY_NIGHT, night)
		env.ambient_light_color = Color(0.85, 0.85, 0.9).lerp(Color(0.55, 0.62, 0.85), night)
	if sun != null:
		sun.light_color = sun.light_color.lerp(Color(0.6, 0.68, 0.95), night)   # moonlight blue

## The lamps and headlights near `p`, nearest first, at most MAX_LIGHTS.
func _gather(p: Vector2) -> void:
	var found: Array = []
	var c := Vector2i((p / 40.0).floor())
	var cells := ceili(LAMP_REACH / 40.0)
	for x in range(c.x - cells, c.x + cells + 1):
		for y in range(c.y - cells, c.y + cells + 1):
			for l in _lamps.get(Vector2i(x, y), PackedVector2Array()):
				if l.distance_to(p) < LAMP_REACH:
					found.append(Vector3(l.x, l.y, LAMP_R))
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
		lamp += pow(maxf(0.0, 1.0 - d / l.z), 2.0)
	return lerpf(1.0, maxf(MOON, minf(1.0, lamp)), night)
