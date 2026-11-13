## Turf map (U): each cell tinted by who holds it, faint by influence where
## nobody does. E5: U again shows the money map instead: each block from red
## (poor) through yellow to green (rich), shops that went under crossed out,
## people sleeping rough as small grey dots. U a third time hides it.
## Read-only; redrawn a few times a second while shown.
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

var mode := 0   # 0 hidden, 1 turf, 2 money
var opened_frame := -1   # R3D13: the 3D view opened the map with this press: do not count it twice

func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"turf_map") and Engine.get_process_frames() != opened_frame:
		mode = (mode + 1) % 3
		visible = mode != 0
		z_index = 20 if mode == 2 else 2   # the money map sits over the roofs
		queue_redraw()
	_left -= delta
	if visible and _left <= 0.0:
		_left = REFRESH_S
		queue_redraw()

func _draw() -> void:
	if mode == 2:
		_draw_money()
		return
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

const POOR := Color("c0392b")
const MIDDLE := Color("d4ac0d")
const RICH := Color("27ae60")

## E5: the money map.
func _draw_money() -> void:
	var data := BlockEconomyData.of(_world)
	if data == null:
		return
	var size := Vector2.ONE * TerritoryData.CELL_M
	for c in data.blocks:
		var w: float = data.blocks[c]["wealth"]
		var col := POOR.lerp(MIDDLE, w * 2.0) if w < 0.5 else MIDDLE.lerp(RICH, (w - 0.5) * 2.0)
		draw_rect(Rect2(Vector2(c) * TerritoryData.CELL_M, size), Color(col, 0.42))
		draw_rect(Rect2(Vector2(c) * TerritoryData.CELL_M, size), Color(col, 0.6), false, 1.0)
	for b in BusinessSystem.all_buildings(_world):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.status >= 2:
			var p := b.position
			draw_line(p + Vector2(-9, -9), p + Vector2(9, 9), Color(0.08, 0.08, 0.08, 0.95), 4.0)
			draw_line(p + Vector2(-9, 9), p + Vector2(9, -9), Color(0.08, 0.08, 0.08, 0.95), 4.0)
	for e in _world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.home_building_id == &"" and n.camp != Vector2.ZERO:
			draw_circle(n.camp, 4.0, Color(0.2, 0.2, 0.25, 0.95))
