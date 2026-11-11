## Turf map (U): each cell tinted by who holds it, faint by influence where
## nobody does. Read-only; redrawn a few times a second while shown.
extends Node2D

@export var world_driver_path: NodePath

const REFRESH_S := 0.5
var _world: World
var _left := 0.0

func _ready() -> void:
	_world = get_node(world_driver_path).world
	visible = false
	z_index = 2
	if not InputMap.has_action(&"turf_map"):
		InputMap.add_action(&"turf_map")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_U
		InputMap.action_add_event(&"turf_map", ev)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"turf_map"):
		visible = not visible
	_left -= delta
	if visible and _left <= 0.0:
		_left = REFRESH_S
		queue_redraw()

func _draw() -> void:
	var t := TerritorySystem.data(_world)
	if t == null:
		return
	var size := Vector2.ONE * TerritoryData.CELL_M
	for c in t.cells:
		var owner := TerritorySystem.controller(t, c)
		var top: StringName = owner
		var top_v := 0.0
		for g in t.cells[c]:
			if t.cells[c][g] > top_v:
				top_v = t.cells[c][g]
				top = g
		if top == &"" or top_v < 5.0:
			continue
		var col: Color = TerritorySystem.GANG_COLORS.get(top, Color.GRAY)
		col.a = 0.35 if owner != &"" else 0.06 + top_v / 100.0 * 0.2
		var r := Rect2(Vector2(c) * TerritoryData.CELL_M, size)
		draw_rect(r, col)
		if owner != &"":
			draw_rect(r, Color(col, 0.9), false, 2.0)
