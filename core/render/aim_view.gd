## Combat C4: the player's aim, drawn Zomboid-style, and the bridge from the
## mouse to the sim (writes PlayerStateData.aim_point each frame; the sim never
## reads the mouse itself).
##   - always: a faint line from the player toward the cursor (facing)
##   - right button held: the cone the next shot can land in, or the fists' reach
##   - a blow or shot: a short tracer to where it stopped
extends Node2D

@export var world_driver_path: NodePath

const FACING_M := 4.0
const TRACER_S := 0.12
const FACING_COLOR := Color(1, 1, 1, 0.25)
const CONE_COLOR := Color(1.0, 0.85, 0.3, 0.18)
const CONE_EDGE := Color(1.0, 0.85, 0.3, 0.6)
const TRACER_COLOR := Color(1.0, 0.95, 0.6, 0.95)
const HIT_COLOR := Color(0.9, 0.15, 0.1, 0.9)

var _world: World
var _seen_attack: Dictionary = {}
var _tracer_left := 0.0

func _ready() -> void:
	_world = get_node(world_driver_path).world
	z_index = 5

func _process(delta: float) -> void:
	var state := _state()
	if state == null:
		return
	state.aim_point = get_global_mouse_position()
	if not is_same(state.last_attack, _seen_attack) and not state.last_attack.is_empty():
		_seen_attack = state.last_attack
		_tracer_left = TRACER_S
	_tracer_left = maxf(0.0, _tracer_left - delta)
	queue_redraw()

func _draw() -> void:
	var state := _state()
	if state == null:
		return
	var me: Vector2 = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC).position
	var dir := (state.aim_point - me).normalized()
	if dir == Vector2.ZERO:
		return
	var px := 1.0 / get_viewport_transform().get_scale().x   # one screen pixel, in metres
	var goal: Variant = JobSystem.target_point(_world, state)
	if goal != null:   # JB1: where the job wants you
		var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() / 250.0)
		draw_arc(goal, 2.5 * pulse, 0.0, TAU, 32, Color(0.95, 0.72, 0.2, 0.9), 3.0 * px)
		var to: Vector2 = goal - me
		if to.length() > 20.0:
			draw_line(me + to.normalized() * 6.0, me + to.normalized() * 10.0, Color(0.95, 0.72, 0.2, 0.9), 4.0 * px)
	draw_line(me, me + dir * FACING_M, FACING_COLOR, 1.5 * px)
	if state.aiming:
		_draw_reach(me, dir, CombatSystem.WEAPONS[state.weapon], px)
	if _tracer_left > 0.0:
		var hit := _seen_attack.has("hit_id")
		draw_line(me + dir * 0.4, _seen_attack["end"], TRACER_COLOR, 2.0 * px)
		if hit:
			draw_circle(_seen_attack["end"], 0.3, HIT_COLOR)

func _draw_reach(me: Vector2, dir: Vector2, w: Dictionary, px: float) -> void:
	var reach: float = w["range"]
	var half: float = deg_to_rad(w["arc_deg"] * 0.5) if w["melee"] else deg_to_rad(w["spread_aim_deg"])
	var cone := PackedVector2Array([me])
	for i in 9:
		cone.append(me + dir.rotated(lerpf(-half, half, i / 8.0)) * reach)
	draw_colored_polygon(cone, CONE_COLOR)
	draw_line(me, cone[1], CONE_EDGE, 1.0 * px)
	draw_line(me, cone[cone.size() - 1], CONE_EDGE, 1.0 * px)

func _state() -> PlayerStateData:
	if _world == null:
		return null
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	return null if player == null else player.get_component(ComponentNames.PLAYER_STATE)
