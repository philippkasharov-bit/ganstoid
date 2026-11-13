## DW2: break-ins you can see on the street: a kicked-in door shows as a dark
## gap with splinters, smashed glass as shards, boarded windows as crossed
## planks, all at the building's door. Screen-space over the map (the cached
## building layer never redraws); the list of marked buildings refreshes once
## a second.
class_name OpeningsView
extends Control

const SIZE := 12.0        # at 12 px/m; marks grow with the zoom
const REFRESH_S := 1.0
const PLANK := Color("8a6a43")

var _world: World
var _marked: Array[BuildingData] = []
var _left := 0.0

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_left -= delta
	if _world != null and _left <= 0.0:
		_left = REFRESH_S
		_marked.clear()
		for e in _world.entities.values():
			var b: BuildingData = e.get_component(ComponentNames.BUILDING)
			if b != null and (b.door_kicked or b.windows_broken > 0 or b.windows_boarded):
				_marked.append(b)
	queue_redraw()

func _draw() -> void:
	var k := clampf(ScreenMap.px_per_m(get_viewport()) / 12.0, 0.8, 2.2)   # R3D13: either view
	var view := get_viewport_rect().grow(SIZE * 2.0 * k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in _marked:
		var at: Vector2 = ScreenMap.to_screen(get_viewport(), b.position, 1.0)
		if not view.has_point(at):
			continue
		draw_set_transform(at, 0.0, Vector2.ONE * k)   # draw the mark around (0,0), scaled
		at = Vector2.ZERO
		if b.door_kicked:
			draw_rect(Rect2(at - Vector2(SIZE * 0.4, SIZE), Vector2(SIZE * 0.8, SIZE)), Color(0.05, 0.04, 0.04))
			for j in 3:
				draw_line(at + Vector2(-SIZE * 0.4 + j * 4.0, -SIZE), at + Vector2(-SIZE * 0.6 + j * 5.0, -SIZE * 1.3), PLANK, 1.5)
		if b.windows_broken > 0:
			_shards(at + Vector2(SIZE, -SIZE * 0.6))
		if b.windows_boarded:
			var c := at + Vector2(-SIZE * 1.2, -SIZE * 0.6)
			draw_line(c - Vector2(SIZE * 0.5, SIZE * 0.4), c + Vector2(SIZE * 0.5, SIZE * 0.4), PLANK, 3.0)
			draw_line(c + Vector2(-SIZE * 0.5, SIZE * 0.4), c + Vector2(SIZE * 0.5, -SIZE * 0.4), PLANK, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _shards(c: Vector2) -> void:
	for j in 3:
		var a := c + Vector2(j * 4.0 - 4.0, 0)
		var tri := PackedVector2Array([a, a + Vector2(3, -6), a + Vector2(5, 1)])
		draw_colored_polygon(tri, Color(0.85, 0.93, 1.0))
		draw_polyline(tri + PackedVector2Array([a]), Color(0.2, 0.25, 0.3), 1.0)
