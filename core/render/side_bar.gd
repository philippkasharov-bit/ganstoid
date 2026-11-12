## UI6: Zomboid's left icon strip: one square button per screen, its key
## under it. A click sends that key's action, so the bar never does anything
## the keyboard cannot.
class_name SideBar
extends VBoxContainer

## [label, key shown, input action, icon name]
const BUTTONS := [
	["Bag", "I", &"inventory", "bag"],
	["Skills", "K", &"skills_window", "skills"],
	["Crew", "Tab", &"ui_focus_next", "crew"],
	["Turf", "U", &"turf_map", "turf"],
]
const SIZE := Vector2(56, 64)

func setup() -> void:
	add_theme_constant_override("separation", 4)
	position = Vector2(10, 150)
	for b in BUTTONS:
		add_child(_button(b[0], b[1], b[2], b[3]))

func _button(label: String, key: String, action: StringName, icon: String) -> Button:
	var b := Button.new()
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := Moodles.icon_or_glyph(icon, label.left(1), 42.0)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(art)
	var k := UiTheme.label(key, UiTheme.FONT_SMALL, UiTheme.ACCENT)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(k)
	b.add_child(stack)
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
