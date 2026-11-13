## INV2/INV6: one item grid, Tarkov/DayZ-style, used twice in the bag window:
## your bag, and the ground/trunk around you ("Nearby"). Draws the cells and
## every pile at its real size, its count in a strip of its own. Drag a pile
## to move it (R turns it; a green or red ghost shows if it lands); drop it on
## the other grid to move it across. Double-click uses, right-click opens its
## menu, hover shows its card. The window owns the data: it sets `piles`, and
## does the moves when this view reports them.
class_name BagGridView
extends Control

signal use_pile(index: int)
signal menu_pile(index: int, at: Vector2)
signal hover_pile(index: int, at: Vector2)
signal hover_end
signal moved(index: int, cell: Vector2i, turned: bool)   # inside this grid
signal moved_out(index: int)                             # dropped on `other`
signal moved_to_hand(index: int)                         # dropped on `hand`

const CELL := 32.0
const COUNT_H := 10.0
const LINE := Color(1, 1, 1, 0.09)
const OK_GHOST := Color(0.36, 0.78, 0.35, 0.35)
const BAD_GHOST := Color(0.86, 0.3, 0.28, 0.35)

var piles: Array = []          # [{id, x, y, r, n}]
var cols := BagGrid.COLS
var rows := BagGrid.ROWS
var other: BagGridView         # the grid a pile can be dropped across to
var hand: Control              # UIF1: the hand slot; dropping a weapon there equips it
var _drag := -1
var _drag_turned := false
var _grab := Vector2.ZERO
var _hovered := -1

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	resize_grid(cols, rows)

func resize_grid(c: int, r: int) -> void:
	cols = c
	rows = r
	custom_minimum_size = Vector2(cols, rows) * CELL

func show_piles(list: Array) -> void:
	piles = list
	if _drag >= piles.size():
		_drag = -1
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	for x in cols + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, rows * CELL), LINE)
	for y in rows + 1:
		draw_line(Vector2(0, y * CELL), Vector2(cols * CELL, y * CELL), LINE)
	for i in piles.size():
		if i != _drag:
			_draw_pile(piles[i], _pile_rect(piles[i]), i == _hovered)
	if _drag >= 0:
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
	var art := inner.grow(-3)   # UI22: nothing printed over the picture
	if int(p["n"]) > 1:
		art.size.y -= COUNT_H
		var strip := Rect2(inner.position.x, inner.end.y - COUNT_H, inner.size.x, COUNT_H)
		draw_rect(strip, Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, strip.position + Vector2(0, COUNT_H - 2), "%d" % int(p["n"]), HORIZONTAL_ALIGNMENT_CENTER, strip.size.x, 8, UiTheme.TEXT)
	ItemArt.draw(self, p["id"], art, col, p["r"])

## The pile under the mouse while dragging, plus a ghost where it would land.
func _draw_drag() -> void:
	var p: Dictionary = piles[_drag]
	var f := BagGrid.footprint(p["id"], _drag_turned)
	if _over_other():
		other.queue_redraw()
	else:
		var at := _drop_cell()
		var ok := BagGrid.fits(BagGrid.occupancy(piles, _drag), at, f, cols, rows)
		draw_rect(Rect2(Vector2(at) * CELL, Vector2(f) * CELL), OK_GHOST if ok else BAD_GHOST)
	var moving := p.duplicate()
	moving["r"] = _drag_turned
	_draw_pile(moving, Rect2(get_local_mouse_position() - _grab, Vector2(f) * CELL), true)

func _drop_cell() -> Vector2i:
	var corner := get_local_mouse_position() - _grab + Vector2(CELL, CELL) * 0.5
	return Vector2i(floori(corner.x / CELL), floori(corner.y / CELL))

func _over_other() -> bool:
	return other != null and other.is_visible_in_tree() and other.get_global_rect().has_point(get_global_mouse_position())

## Short name of an item (lists, the Nearby rows).
const SHORT := {&"water": "H2O", &"soda": "SODA", &"coffee": "JOE", &"chips": "CHIPS", &"burrito": "BURR",
	&"bandage": "BNDG", &"bat": "BAT", &"knife": "KNIFE", &"pistol": "9MM", &"pistol_clean": "9MM+", &"ammo": "AMMO"}

static func _short(id: StringName) -> String:
	return SHORT.get(id, String(id).left(5).to_upper())

func pile_at(local: Vector2) -> int:
	return BagGrid.occupancy(piles).get(Vector2i(floori(local.x / CELL), floori(local.y / CELL)), -1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventMouseMotion:
		_on_motion(event)

func _on_button(e: InputEventMouseButton) -> void:
	var hit := pile_at(e.position)
	if e.button_index == MOUSE_BUTTON_LEFT and e.pressed and e.double_click and hit >= 0:
		_drag = -1
		use_pile.emit(hit)
	elif e.button_index == MOUSE_BUTTON_LEFT and e.pressed and hit >= 0:
		_drag = hit
		_drag_turned = piles[hit]["r"]
		_grab = e.position - _pile_rect(piles[hit]).position
		hover_end.emit()
	elif e.button_index == MOUSE_BUTTON_LEFT and not e.pressed and _drag >= 0:
		_release()
	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and hit >= 0:
		menu_pile.emit(hit, get_global_mouse_position())
	queue_redraw()

## Dropped: across onto the other grid, or to a cell here (a bad spot snaps back).
func _release() -> void:
	var index := _drag
	_drag = -1
	if hand != null and hand.get_global_rect().has_point(get_global_mouse_position()):
		moved_to_hand.emit(index)
	elif _over_other():
		moved_out.emit(index)
		other.queue_redraw()
	else:
		moved.emit(index, _drop_cell(), _drag_turned)

func _on_motion(e: InputEventMouseMotion) -> void:
	var hit := -1 if _drag >= 0 else pile_at(e.position)
	if hit != _hovered:
		_hovered = hit
		if hit >= 0:   # UIF1: the card sits beside the pile, not over its neighbours
			var r := _pile_rect(piles[hit])
			hover_pile.emit(hit, global_position + Vector2(r.end.x, r.position.y) - Vector2(8, 16))
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
