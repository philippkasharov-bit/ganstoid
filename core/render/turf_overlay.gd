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
	if Input.is_action_just_pressed(&"turf_map") and Engine.get_process_frames() != opened_frame and not ScreenMap.is_3d():
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
		if Hoods.is_street(c) and Hoods.data() != null:   # T2: a street: its blocks shaded, the street itself drawn bold
			for poly in Hoods.data().blocks_of(c):
				draw_colored_polygon(poly, col)
			draw_polyline(Hoods.data().street(c).get("pts", PackedVector2Array()), Color(col, 0.95), 5.0 if owner != &"" else 2.5)
			continue
		var shape := _shape(c)   # T1: a block, or the old grid square
		draw_colored_polygon(shape, col)
		if owner != &"":
			draw_polyline(shape + PackedVector2Array([shape[0]]), Color(col, 0.9), 2.0)
	_hood_names()

## T1: a block's outline on the map, or the old grid square off the blocks.
static func _shape(c: Vector2i) -> PackedVector2Array:
	var b: Dictionary = Hoods.data().block(c) if Hoods.data() != null else {}
	if not b.is_empty():
		return b["poly"]
	var r := Rect2(Vector2(c) * TerritoryData.CELL_M, Vector2.ONE * TerritoryData.CELL_M)
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

## T1: every hood's name over it, its district under it.
func _hood_names() -> void:
	var h := Hoods.data()
	if h == null:
		return
	var px := 1.0 / maxf(get_viewport_transform().get_scale().x, 0.001)
	for name in h.hood_centres():
		var at: Vector2 = h.hood_centres()[name]
		draw_string(ThemeDB.fallback_font, at, name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, -1, int(16 * px), Color(1, 1, 1, 0.85))
		draw_string(ThemeDB.fallback_font, at + Vector2(0, 14 * px), h.districts.get(name, ""), HORIZONTAL_ALIGNMENT_CENTER, -1, int(11 * px), Color(1, 1, 1, 0.6))

const POOR := Color("c0392b")
const MIDDLE := Color("d4ac0d")
const RICH := Color("27ae60")

## E5: the money map.
func _draw_money() -> void:
	var data := BlockEconomyData.of(_world)
	if data == null:
		return
	for c in data.blocks:
		var w: float = data.blocks[c]["wealth"]
		var col := POOR.lerp(MIDDLE, w * 2.0) if w < 0.5 else MIDDLE.lerp(RICH, (w - 0.5) * 2.0)
		var shape := _shape(c)
		draw_colored_polygon(shape, Color(col, 0.42))
		draw_polyline(shape + PackedVector2Array([shape[0]]), Color(col, 0.6), 1.0)
	for b in BusinessSystem.all_buildings(_world):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.status >= 2:
			var p := b.position
			draw_line(p + Vector2(-9, -9), p + Vector2(9, 9), Color(0.08, 0.08, 0.08, 0.95), 4.0)
			draw_line(p + Vector2(-9, 9), p + Vector2(9, -9), Color(0.08, 0.08, 0.08, 0.95), 4.0)
	for e in _world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.home_building_id == &"" and n.camp != Vector2.ZERO:
			draw_circle(n.camp, 4.0, Color(0.2, 0.2, 0.25, 0.95))
