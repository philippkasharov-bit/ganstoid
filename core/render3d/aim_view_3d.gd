## R3D12: AimView in 3D: writes the player's aim from the mouse (cast onto
## the ground through ScreenMap) and draws, flat on the ground: a faint
## facing line, the reach of the next swing or shot while aiming, and the
## job's goal ring. No tracers (standing rule: no gun tracing).
class_name AimView3D
extends MeshInstance3D

const FACING_M := 4.0
const LIFT := 0.06
const FACING_COLOR := Color(1, 1, 1, 0.35)
const CONE_COLOR := Color(1.0, 0.85, 0.3, 0.22)
const MARK_COLOR := Color(0.55, 1.0, 0.65, 0.55)
const GOAL_COLOR := Color(0.95, 0.72, 0.2, 0.9)

var world: World
var origin := Vector2.ZERO
var _lines := ImmediateMesh.new()

func _ready() -> void:
	mesh = _lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true   # A2b: right in Mobile too
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta: float) -> void:
	_lines.clear_surfaces()
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	if player == null:
		return
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	var me: Vector2 = (player.get_component(ComponentNames.NPC) as NPCData).position
	state.aim_point = ScreenMap.to_map(get_viewport(), get_viewport().get_mouse_position())
	var dir := (state.aim_point - me).normalized()
	_lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(me, 0.55, MARK_COLOR)   # P1: you, among the crowd (drawn even with the mouse on you)
	if dir != Vector2.ZERO:
		_strip(me + dir * 0.6, me + dir * FACING_M, 0.05, FACING_COLOR)
	if state.aiming and dir != Vector2.ZERO:
		_cone(me, dir, CombatSystem.WEAPONS[state.weapon])
	var goal: Variant = JobSystem.target_point(world, state)
	if goal != null:
		_ring(goal, 2.5 * (1.0 + 0.25 * sin(Time.get_ticks_msec() / 250.0)), GOAL_COLOR)
	_lines.surface_end()

func _v(p: Vector2) -> Vector3:
	return Vector3(p.x - origin.x, LIFT, p.y - origin.y)

func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	for p in [a, b, c]:
		_lines.surface_set_color(col)
		_lines.surface_add_vertex(_v(p))

## A thin flat line a-b, `w` metres wide.
func _strip(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := (b - a).normalized().orthogonal() * w
	_tri(a - n, b - n, b + n, col)
	_tri(a - n, b + n, a + n, col)

func _cone(me: Vector2, dir: Vector2, w: Dictionary) -> void:
	var reach: float = w["range"]
	var half: float = deg_to_rad(w["arc_deg"] * 0.5) if w["melee"] else deg_to_rad(w["spread_aim_deg"])
	for i in 8:
		var a := me + dir.rotated(lerpf(-half, half, i / 8.0)) * reach
		var b := me + dir.rotated(lerpf(-half, half, (i + 1) / 8.0)) * reach
		_tri(me, a, b, CONE_COLOR)

func _ring(c: Vector2, r: float, col: Color) -> void:
	for i in 32:
		var a := c + Vector2.from_angle(i * TAU / 32.0) * r
		var b := c + Vector2.from_angle((i + 1) * TAU / 32.0) * r
		_strip(a, b, 0.12 if r > 1.0 else 0.04, col)
