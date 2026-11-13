## UI1: the E menu: everything you can do where you stand.
class_name ActionMenu
extends UiPanel

func refresh() -> void:
	var state := player_state()
	if state == null or state.menu_options.is_empty():
		visible = false
		return
	if not visible:   # UIF1: opens at the mouse, like Zomboid's right-click menu
		var screen := get_viewport_rect().size
		position = (get_viewport().get_mouse_position() + Vector2(12, 12)).clamp(Vector2.ZERO, screen - Vector2(260, 200))
	var rows: Array = []
	for i in state.menu_options.size():
		rows.append([str(i + 1), state.menu_options[i], state.menu_notes[i] if i < state.menu_notes.size() else ""])
	show_panel(state.menu_title if state.menu_title != "" else "What now?", rows, [["Esc", "back"]])
