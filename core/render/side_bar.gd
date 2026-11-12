## UI6: Zomboid's left icon strip: one square button per screen, its key
## under it. A click sends that key's action, so the bar never does anything
## the keyboard cannot.
class_name SideBar
extends VBoxContainer

## [label, key shown, input action]
const BUTTONS := [
	["Bag", "I", &"inventory"],
	["Skills", "K", &"skills_window"],
	["Crew", "Tab", &"ui_focus_next"],
	["Turf", "U", &"turf_map"],
]
const SIZE := Vector2(54, 50)

func setup() -> void:
	add_theme_constant_override("separation", 4)
	position = Vector2(10, 150)
	for b in BUTTONS:
		add_child(_button(b[0], b[1], b[2]))

func _button(label: String, key: String, action: StringName) -> Button:
	var b := Button.new()
	b.text = "%s\n%s" % [label, key]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = SIZE
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.BG))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BG_HEADER, UiTheme.ACCENT))
	b.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.BG_ROW_SELECT, UiTheme.ACCENT))
	b.tooltip_text = "%s (%s)" % [label, key]
	b.pressed.connect(func() -> void: _send(action))
	return b

func _send(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
