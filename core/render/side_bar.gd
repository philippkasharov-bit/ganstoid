## UI6/UI23: Zomboid's left icon strip: one square icon per screen; its name
## and key show on hover. A click sends that key's action, so the bar never does anything
## the keyboard cannot.
class_name SideBar
extends VBoxContainer

## [label, key shown, input action, icon name]
const BUTTONS := [
	["Bag", "I", &"inventory", "bag"],
	["Character", "K", &"skills_window", "skills"],
	["Health", "H", &"health_window", "medkit"],
	["Crew", "Tab", &"ui_focus_next", "crew"],
	["Turf", "U", &"turf_map", "turf"],
]
const SIZE := Vector2(40, 40)


var _world: World
var _idle_box := UiTheme.button_box("idle")
var _active_box := UiTheme.button_box("on")

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 3)
	position = Vector2(UiTheme.MARGIN, 124)
	for b in BUTTONS:
		add_child(_button(b[0], b[1], b[2], b[3]))

func _button(label: String, key: String, action: StringName, icon: String) -> Button:
	var b := Button.new()
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := Moodles.icon_or_glyph(icon, label.left(1), 32.0)   # UI23: just the icon; name and key on hover
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(art)
	b.add_child(stack)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = SIZE
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	b.add_theme_stylebox_override("normal", _idle_box)
	b.add_theme_stylebox_override("hover", UiTheme.button_box("hover"))
	b.add_theme_stylebox_override("pressed", UiTheme.button_box("on"))
	b.tooltip_text = "%s (%s)" % [label, key]
	b.pressed.connect(func() -> void: _send(action))
	return b

func _send(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)

## UIF1: hidden until a life has begun (the difficulty choice comes first).
## UIF2: the button of an open window gets the gold frame.
func _process(_delta: float) -> void:
	visible = _world != null and GameRules.of(_world) != null
	if not visible:
		return
	var open := _open_windows()
	for i in get_child_count():
		var b := get_child(i) as Button
		if b != null:
			b.add_theme_stylebox_override("normal", _active_box if open.has(BUTTONS[i][0]) else _idle_box)

## Button labels whose window is showing right now.
func _open_windows() -> Dictionary:
	var out := {}
	for n in get_parent().get_children():
		if n is InventoryWindow and n.visible:
			out["Bag"] = true
		elif n is CharacterWindow and n.visible:
			out["Character"] = true
		elif n is HealthWindow and n.visible:
			out["Health"] = true
		elif n is CrewRoster and n.visible:
			out["Crew"] = true
	return out
