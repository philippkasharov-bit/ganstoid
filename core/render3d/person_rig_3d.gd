## D1: box people that move like people. Six parts per person (two legs,
## two arms, torso, head), each a MultiMesh, so a crowd still costs six draw
## calls. Legs and arms swing from hip and shoulder in step with how far the
## person actually moved (a walk swings gently, a run hard, standing still
## not at all, settling back smoothly), the body bobs with each step,
## crouching lowers everyone's parts, and someone down lies flat.
class_name PersonRig3D
extends Node3D

const STRIDE_M := 1.5          # one full leg cycle covers this much ground
const WALK_SWING := 0.5        # radians at a walk
const RUN_SWING := 0.85
const RUN_SPEED := 2.6         # m/s from which the swing is a run
const SETTLE := 10.0           # how fast the swing eases in and out
const LEGS := Color(0.16, 0.17, 0.22)
## part: [size, pivot (x forward, y up, z side), hang below the pivot]
const PARTS := {
	"leg_l": [Vector3(0.2, 0.85, 0.18), Vector3(0, 0.85, -0.12), 0.425],
	"leg_r": [Vector3(0.2, 0.85, 0.18), Vector3(0, 0.85, 0.12), 0.425],
	"arm_l": [Vector3(0.13, 0.62, 0.13), Vector3(0, 1.5, -0.33), 0.31],
	"arm_r": [Vector3(0.13, 0.62, 0.13), Vector3(0, 1.5, 0.33), 0.31],
	"torso": [Vector3(0.3, 0.68, 0.52), Vector3(0, 1.2, 0), 0.0],
	"head": [Vector3(0.28, 0.28, 0.28), Vector3(0, 1.72, 0), 0.0],
}

var origin := Vector2.ZERO
var _layers := {}
var _gait := {}   # id -> [last point, phase, swing]

func _init(count: int = 1500) -> void:
	for part in PARTS:
		_layers[part] = _layer(PARTS[part][0], count)
		add_child(_layers[part])

func set_count(n: int) -> void:
	for l in _layers.values():
		l.multimesh.visible_instance_count = n

## [phase, swing] for `id` now at `at`: phase runs with the ground covered.
func gait(id: StringName, at: Vector2, delta: float) -> Array:
	var g: Array = _gait.get(id, [at, 0.0, 0.0])
	var moved: float = at.distance_to(g[0])
	if moved > 3.0:
		moved = 0.0   # a jump (indoors, a teleport), not a step
	var speed := moved / maxf(delta, 0.001)
	var want := 0.0 if speed < 0.2 else (RUN_SWING if speed > RUN_SPEED else WALK_SWING)
	g = [at, fmod(g[1] + moved / STRIDE_M * TAU, TAU), lerpf(g[2], want, minf(1.0, delta * SETTLE))]
	_gait[id] = g
	return [g[1], g[2]]

func forget(id: StringName) -> void:
	_gait.erase(id)

## Person `i` at map point `at`, facing `face`; pose: phase, swing, down, crouched.
func place(i: int, at: Vector2, face: float, phase: float, swing: float, down: bool, crouched: bool, shirt: Color, skin: Color) -> void:
	var body := Basis(Vector3.UP, -face)
	var base := Vector3(at.x - origin.x, 0.0, at.y - origin.y)
	if down:
		body = body * Basis(Vector3.BACK, PI * 0.5)   # lying along the way they faced
		base.y = 0.16
	var squat := 0.8 if crouched else 1.0
	var bob := absf(sin(phase)) * swing * 0.08   # up on each step
	var s := sin(phase) * swing
	var swings := {"leg_l": s, "leg_r": -s, "arm_l": -s * 0.8, "arm_r": s * 0.8, "torso": 0.0, "head": 0.0}
	var cols := {"leg_l": LEGS, "leg_r": LEGS, "arm_l": shirt, "arm_r": shirt, "torso": shirt, "head": skin}
	for part in PARTS:
		var spec: Array = PARTS[part]
		var pivot: Vector3 = spec[1] * Vector3(1, squat, 1) + Vector3(0, bob, 0)
		var swing_b := Basis(Vector3.BACK, swings[part])
		var local := Transform3D(swing_b, pivot) * Transform3D(Basis(), Vector3(0, -spec[2], 0))
		var mm: MultiMesh = _layers[part].multimesh
		mm.set_instance_transform(i, Transform3D(body, base) * local)
		mm.set_instance_color(i, cols[part])

static func _layer(size: Vector3, count: int) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
