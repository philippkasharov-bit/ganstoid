## UI1/WM1: the action menu: everything you can do where you stand. Opens at
## the cursor on a quick right-click in the world (Zomboid) or on E. A long
## list opens on its categories; hover or click a category and its list flies
## out beside it, the category row staying lit. 1-9 pick in the open list,
## Esc steps back, then closes. Writes only state.ui_pick / ui_pick_parent.
class_name ActionMenu
extends UiPanel

const FLY_TOP := 38.0       # the fly-out's first row lines up with its category
var _sub := UiPanel.new()   # the fly-out
var _serial := -1

func setup(world: World, at: Vector2) -> void:
	super.setup(world, at)
	_sub.setup(world, at)
	_sub.top_level = true
	add_child.call_deferred(_sub)   # inside a container it would be laid out with the rows; top_level keeps it free
	row_hovered.connect(_on_hover)

func refresh() -> void:
	var state := player_state()
	if state == null or state.menu_options.is_empty():
		visible = false
		_sub.visible = false
		return
	if state.menu_serial != _serial or not visible:   # opens where you clicked
		_serial = state.menu_serial
		var screen := get_viewport_rect().size
		position = (get_viewport().get_mouse_position() + Vector2(4, 4)).clamp(Vector2.ZERO, screen - Vector2(260, 200))
	var flying := not state.menu_parent.is_empty()
	var main_rows := _rows_of(state.menu_parent, PackedStringArray(), false) if flying else _rows_of(state.menu_options, state.menu_notes)
	lit_row = state.menu_parent_on if flying else -1
	show_panel("What now?" if flying else (state.menu_title if state.menu_title != "" else "What now?"), main_rows, [["Esc", "back"]])
	_sub.visible = flying
	if flying:
		_sub.show_panel(state.menu_title, _rows_of(state.menu_options, state.menu_notes), [])
		var row := row_rect(state.menu_parent_on)
		var screen := get_viewport_rect().size
		var first := _sub._rows.global_position.y - _sub.global_position.y   # title + rule above the first row
		var at := Vector2(get_global_rect().end.x - 2, row.position.y - (first if first > 0.0 else FLY_TOP))
		if at.x + _sub.size.x > screen.x:   # no room on the right: fly out to the left
			at.x = global_position.x - _sub.size.x + 2
		_sub.position = at.clamp(Vector2.ZERO, (screen - _sub.size).max(Vector2.ZERO))

## numbered: the list 1-9 pick in; the category list beside a fly-out is not.
static func _rows_of(labels: PackedStringArray, notes: PackedStringArray, numbered := true) -> Array:
	var rows: Array = []
	for i in labels.size():
		rows.append([str(i + 1) if numbered else "-", labels[i], notes[i] if i < notes.size() else ""])
	return rows

## Clicks: on the category list while a fly-out shows, open that category;
## anywhere else, the row itself.
func _on_row(index: int) -> void:
	var state := player_state()
	if state == null:
		return
	if not state.menu_parent.is_empty():
		state.ui_pick_parent = index
	else:
		state.ui_pick = index

## Zomboid opens a category's list on hover, not only on click.
func _on_hover(index: int) -> void:
	var state := player_state()
	if state == null:
		return
	var labels := state.menu_parent if not state.menu_parent.is_empty() else state.menu_options
	if index < labels.size() and labels[index].ends_with("›"):
		state.ui_pick_parent = index
