## D1: cars as more than two boxes: a body, a glass cabin set a little back,
## four dark wheels that turn as the car rolls (by the ground it covers),
## and lamps: white headlights in front, red tail lights behind, lit at night
## when someone is at the wheel. MultiMeshes, so the whole street is a few
## draw calls. Each car glides between its last two sim poses.
class_name CarRig3D
extends Node3D

const SNAP_M := 6.0
const CABIN := Color(0.32, 0.4, 0.48)
const TYRE := Color(0.08, 0.08, 0.09)
const WHEEL_R := 0.34
const HEAD := Color(1.0, 0.95, 0.8)
const TAIL := Color(0.85, 0.08, 0.06)

var origin := Vector2.ZERO
var _body := PersonRig3D._layer(Vector3.ONE, 0)
var _cabin := PersonRig3D._layer(Vector3.ONE, 0)
var _wheels := PersonRig3D._layer(Vector3(1, 1, 1), 0)
var _lamps := PersonRig3D._layer(Vector3(1, 1, 1), 0)
var _ticks: Dictionary = {}   # car id -> [was pos, was heading, now pos, now heading, wheel turn]

func _init(count: int = 600) -> void:
	for pair in [[_body, "car_body"], [_cabin, "car_cabin"]]:   # M1: Blender models, unit box, stretched per car
		var m := PersonRig3D.model_mesh(pair[1])
		if m != null:
			pair[0].multimesh.mesh = m
	for l in [_body, _cabin, _wheels, _lamps]:
		l.multimesh.instance_count = count * (4 if l == _wheels or l == _lamps else 1)
		add_child(l)
	_wheels.multimesh.mesh = _wheel_mesh()
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamps.material_override = glow

func set_count(n: int) -> void:
	for l in [_body, _cabin]:
		l.multimesh.visible_instance_count = n
	_wheels.multimesh.visible_instance_count = n * 4
	_lamps.multimesh.visible_instance_count = n * 4

## Car `i`: drawn between its last two sim poses, painted `paint`, lamps on when `lit`.
func place(i: int, id: StringName, car: VehicleData, paint: Color, shade: float, lit: bool) -> void:
	var pose := _between(id, car)
	var turn := Basis(Vector3.UP, -pose[1])
	var at := Vector3(pose[0].x - origin.x, 0, pose[0].y - origin.y)
	var l := car.length_m
	var w := car.width_m
	_body.multimesh.set_instance_transform(i, Transform3D(turn.scaled_local(Vector3(l, 0.62, w)), at + Vector3(0, 0.68, 0)))
	_body.multimesh.set_instance_color(i, paint * shade)
	_cabin.multimesh.set_instance_transform(i, Transform3D(turn.scaled_local(Vector3(l * 0.48, 0.48, w * 0.86)), at + turn * Vector3(-l * 0.06, 0, 0) + Vector3(0, 1.22, 0)))
	_cabin.multimesh.set_instance_color(i, CABIN * shade)
	var spin: float = pose[2]
	for k in 4:
		var off := Vector3((l * 0.32) * (1 if k < 2 else -1), WHEEL_R, (w * 0.5) * (1 if k % 2 == 0 else -1))
		_wheels.multimesh.set_instance_transform(i * 4 + k, Transform3D(turn * Basis(Vector3.BACK, -spin), at + turn * off))
		_wheels.multimesh.set_instance_color(i * 4 + k, TYRE)
		var front := k < 2
		var lamp := Vector3((l * 0.5 + 0.01) * (1 if front else -1), 0.75, (w * 0.32) * (1 if k % 2 == 0 else -1))
		var col: Color = (HEAD if front else TAIL) * (1.0 if lit else 0.45)
		_lamps.multimesh.set_instance_transform(i * 4 + k, Transform3D(turn.scaled_local(Vector3(0.05, 0.14, 0.32)), at + turn * lamp))
		_lamps.multimesh.set_instance_color(i * 4 + k, col)

## [position, heading, wheel turn] between the last two sim poses.
func _between(id: StringName, car: VehicleData) -> Array:
	var t: Array = _ticks.get(id, [car.position, car.heading, car.position, car.heading, 0.0])
	if car.position != t[2] or car.heading != t[3]:
		var jump: bool = car.position.distance_to(t[2]) > SNAP_M
		var rolled: float = 0.0 if jump else car.position.distance_to(t[2]) * signf(car.speed) / WHEEL_R
		t = [car.position if jump else t[2], car.heading if jump else t[3], car.position, car.heading, fmod(t[4] + rolled, TAU)]
		_ticks[id] = t
	var f := Engine.get_physics_interpolation_fraction()
	return [(t[0] as Vector2).lerp(t[2], f), lerp_angle(t[1], t[3], f), t[4]]

## A wheel: a short dark cylinder on its side, with a hub so the turn shows.
static func _wheel_mesh() -> ArrayMesh:
	var tyre := CylinderMesh.new()
	tyre.top_radius = WHEEL_R
	tyre.bottom_radius = WHEEL_R
	tyre.height = 0.24
	tyre.radial_segments = 8
	var st := SurfaceTool.new()
	st.append_from(tyre, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	var hub := BoxMesh.new()
	hub.size = Vector3(WHEEL_R * 1.4, 0.08, 0.26)
	st.append_from(hub, 0, Transform3D())
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh
