## UI1: the E menu: everything you can do where you stand.
class_name ActionMenu
extends UiPanel

func refresh() -> void:
	var state := player_state()
	if state == null or state.menu_options.is_empty():
		visible = false
		return
	var rows: Array = []
	for i in state.menu_options.size():
		rows.append([str(i + 1), state.menu_options[i], ""])
	show_panel("What now?", rows, "1-9 choose    E / Esc close")
