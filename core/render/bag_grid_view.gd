## INV2: the bag grid, Tarkov/DayZ-style. Draws the cells and every pile at
## its real size (picture, short name, count). Drag a pile to move it (R turns
## it while dragging; a green or red ghost shows if it lands), double-click to
## use it, right-click for its menu, hover for its card. Moves go straight to
## BagGrid (layout only); using goes out as a signal for the window to send.
class_name BagGridView
extends Control

signal use_item(id: StringName)
signal menu_item(id: StringName, at: Vector2)
signal hover_item(id: StringName, at: Vector2)
signal hover_end

const CELL := 32.0
const LINE := Color(1, 1, 1, 0.09)
const OK_GHOST := Color(0.36, 0.78, 0.35, 0.35)
const BAD_GHOST := Color(0.86, 0.3, 0.28, 0.35)

var state: PlayerStateData
var _drag := -1
var _drag_turned := false
var _grab := Vector2.ZERO
var _hovered := -1

func _init() -> void:
	custom_minimum_size = Vector2(BagGrid.COLS, BagGrid.ROWS) * CELL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	for x in BagGrid.COLS + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, BagGrid.ROWS * CELL), LINE)
	for y in BagGrid.ROWS + 1:
		draw_line(Vector2(0, y * CELL), Vector2(BagGrid.COLS * CELL, y * CELL), LINE)
	if state == null:
		return
	for i in state.bag.size():
		if i != _drag:
			_draw_pile(state.bag[i], _pile_rect(state.bag[i]), i == _hovered)
	if _drag >= 0 and _drag < state.bag.size():
		_draw_drag()

func _pile_rect(p: Dictionary) -> Rect2:
	var f := BagGrid.footprint(p["id"], p["r"])
	return Rect2(Vector2(p["x"], p["y"]) * CELL, Vector2(f) * CELL)

func _draw_pile(p: Dictionary, r: Rect2, lit: bool) -> void:
	var kind: String = ItemCatalog.item(p["id"]).get("kind", "goods")
	var col: Color = InventoryWindow.KIND_COLOURS.get(kind, UiTheme.DIM)
	var inner := r.grow(-1.5)
	draw_rect(inner, Color(0.02, 0.02, 0.03, 0.55) if not lit else Color(col, 0.22))
	draw_rect(inner, Color(col, 0.75), false, 1.0)
	ItemArt.draw(self, p["id"], inner.grow(-3), col, p["r"])
	var font := UiTheme.font("bungee")
	draw_string(font, inner.position + Vector2(3, 10), _short(p["id"]), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 4, 7, Color(1, 1, 1, 0.85))
	if int(p["n"]) > 1:
		draw_string(font, inner.end - Vector2(inner.size.x - 2, 3), "x%d" % int(p["n"]), HORIZONTAL_ALIGNMENT_RIGHT, inner.size.x - 4, 9, UiTheme.ACCENT)

## The pile under the mouse while dragging, plus a ghost on the cells it would take.
func _draw_drag() -> void:
	var p: Dictionary = state.bag[_drag]
	var f := BagGrid.footprint(p["id"], _drag_turned)
	var at := _drop_cell()
	var ok := BagGrid.fits(BagGrid.occupancy(state.bag, _drag), at, f)
	draw_rect(Rect2(Vector2(at) * CELL, Vector2(f) * CELL), OK_GHOST if ok else BAD_GHOST)
	var moved := p.duplicate()
	moved["r"] = _drag_turned
	_draw_pile(moved, Rect2(get_local_mouse_position() - _grab, Vector2(f) * CELL), true)

func _drop_cell() -> Vector2i:
	var corner := get_local_mouse_position() - _grab + Vector2(CELL, CELL) * 0.5
	return Vector2i(floori(corner.x / CELL), floori(corner.y / CELL))

## Short label for the corner of a pile (Tarkov prints a short name too).
const SHORT := {&"water": "H2O", &"soda": "SODA", &"coffee": "JOE", &"chips": "CHIPS", &"burrito": "BURR",
	&"bandage": "BNDG", &"bat": "BAT", &"knife": "KNIFE", &"pistol": "9MM", &"pistol_clean": "9MM+", &"ammo": "AMMO"}

static func _short(id: StringName) -> String:
	return SHORT.get(id, String(id).left(5).to_upper())

func pile_at(local: Vector2) -> int:
	if state == null:
		return -1
	return BagGrid.occupancy(state.bag).get(Vector2i(floori(local.x / CELL), floori(local.y / CELL)), -1)

func _gui_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventMouseMotion:
		_on_motion(event)

func _on_button(e: InputEventMouseButton) -> void:
	var hit := pile_at(e.position)
	if e.button_index == MOUSE_BUTTON_LEFT and e.pressed and e.double_click and hit >= 0:
		_drag = -1
		use_item.emit(state.bag[hit]["id"])
	elif e.button_index == MOUSE_BUTTON_LEFT and e.pressed and hit >= 0:
		_drag = hit
		_drag_turned = state.bag[hit]["r"]
		_grab = e.position - _pile_rect(state.bag[hit]).position
		hover_end.emit()
	elif e.button_index == MOUSE_BUTTON_LEFT and not e.pressed and _drag >= 0:
		BagGrid.move(state, _drag, _drop_cell(), _drag_turned)   # a bad spot snaps back
		_drag = -1
	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and hit >= 0:
		menu_item.emit(state.bag[hit]["id"], get_global_mouse_position())
	queue_redraw()

func _on_motion(e: InputEventMouseMotion) -> void:
	var hit := -1 if _drag >= 0 else pile_at(e.position)
	if hit != _hovered:
		_hovered = hit
		if hit >= 0:
			hover_item.emit(state.bag[hit]["id"], get_global_mouse_position())
		else:
			hover_end.emit()
	queue_redraw()

## R turns the pile you are dragging (Tarkov).
func _input(event: InputEvent) -> void:
	if _drag >= 0 and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_drag_turned = not _drag_turned
		get_viewport().set_input_as_handled()
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _drag < 0:
		_hovered = -1
		hover_end.emit()
		queue_redraw()
