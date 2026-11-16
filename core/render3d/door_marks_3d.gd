## CV1: the way in, easy to find. A warm, unlit doormat glows on the ground at
## the front door of each building within NEAR_M of you, and of every building
## the cutaway is cutting (their walls are down to a low stub, so the door is
## hard to read). Read-only: positions come from the city data.
class_name DoorMarks3D
extends Node3D

const NEAR_M := 18.0
const MAX := 24
const SIZE := Vector3(1.8, 0.03, 1.1)    # along the wall, height, out from it
const OUT_M := 0.75                       # from the wall to the mat's middle
const COLOR := Color(1.0, 0.72, 0.18, 0.92)

var origin := Vector2.ZERO
var footprints: Footprints
var _marks: Array[MeshInstance3D] = []

func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = COLOR
	mesh.material = mat
	for i in MAX:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_marks.append(m)

## Marks the doors of the buildings near `you` and of those tagged `cut`.
func show_for(you: Vector2, cut: PackedInt32Array) -> void:
	var picked: Array = []
	if footprints != null and you != Vector2.INF:
		for tag in cut:
			_add(picked, footprints.building_of(tag))
		for entry in footprints.near_point(you, NEAR_M):
			_add(picked, entry[3])
	for i in _marks.size():
		var m := _marks[i]
		m.visible = i < picked.size()
		if m.visible:
			m.transform = place(picked[i]["door"], picked[i]["poly"], origin)

func _add(picked: Array, b: Dictionary) -> void:
	if picked.size() < MAX and not b.is_empty() and b.has("door") and not picked.has(b):
		picked.append(b)

## The mat's transform: on the ground against the wall nearest `door` (the
## city's door point stands a little out on the path), lying along that wall.
static func place(door: Vector2, poly: PackedVector2Array, at: Vector2) -> Transform3D:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= maxf(1.0, poly.size())
	var best := door
	var along := Vector2.RIGHT
	var best_d := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if a == b:
			continue
		var q := Geometry2D.get_closest_point_to_segment(door, a, b)
		if q.distance_to(door) < best_d:
			best_d = q.distance_to(door)
			best = q
			along = (b - a).normalized()
	var out := Vector2(-along.y, along.x)
	if out.dot(best - c) < 0.0:
		out = -out
	var p := best + out * OUT_M - at
	var basis := Basis(Vector3.UP, -along.angle())
	return Transform3D(basis, Vector3(p.x, 0.04, p.y))
