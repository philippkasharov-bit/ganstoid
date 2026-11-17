## UI6: F10, layout mode. The game pauses its HUD clicks; every movable panel
## gets a dashed outline and its name, and dragging one moves it (saved). F10
## or Esc ends it; the pause menu has "Reset HUD layout". J and O hide or show
## the pager and the minimap at any time.
class_name LayoutEditor
extends Control

var panels: Dictionary = {}     # id -> Control
var _drag := ""
var _hint := Label.new()

func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudLayout.bind_keys()
	_hint.text = "LAYOUT MODE   drag a panel to move it   ·   J pager   O minimap   ·   F10 or Esc: done   ·   Esc menu: Reset HUD layout"
	_hint.add_theme_font_override("font", UiTheme.font("bungee"))
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", UiTheme.ACCENT)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_hint)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(HudLayout.EDIT_ACTION) or (HudLayout.editing and Input.is_action_just_pressed("ui_cancel")):
		if HudLayout.editing:
			HudLayout.done_editing()
		else:
			HudLayout.editing = true
	for id in HudLayout.PANELS:
		var action: StringName = HudLayout.PANELS[id][1]
		if action != &"" and Input.is_action_just_pressed(action):
			HudLayout.toggle(id)
	mouse_filter = Control.MOUSE_FILTER_STOP if HudLayout.editing else Control.MOUSE_FILTER_IGNORE
	_hint.visible = HudLayout.editing
	_hint.position = Vector2((get_viewport_rect().size.x - _hint.size.x) * 0.5, get_viewport_rect().size.y * 0.5)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not HudLayout.editing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = _under(event.position) if event.pressed else ""
		accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		HudLayout.move(_drag, event.relative)
		accept_event()

func _under(p: Vector2) -> String:
	for id in panels:
		var c: Control = panels[id]
		if c.visible and Rect2(c.position, c.size).has_point(p):
			return id
	return ""

func _draw() -> void:
	if not HudLayout.editing:
		return
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.25))
	for id in panels:
		var c: Control = panels[id]
		if not c.visible:
			continue
		var r := Rect2(c.position, c.size).grow(3)
		draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), UiTheme.ACCENT, 2.0, 6.0)
		draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, UiTheme.ACCENT, 2.0, 6.0)
		draw_dashed_line(r.end, Vector2(r.position.x, r.end.y), UiTheme.ACCENT, 2.0, 6.0)
		draw_dashed_line(Vector2(r.position.x, r.end.y), r.position, UiTheme.ACCENT, 2.0, 6.0)
		var name: String = HudLayout.PANELS[id][0]
		var key: int = HudLayout.PANELS[id][2]
		if key != KEY_NONE:
			name += "  (%s hides)" % OS.get_keycode_string(key)
		var label_at := r.position + (Vector2(4, -6) if r.position.y > 18.0 else Vector2(4, r.size.y + 16))   # under it at the top edge
		draw_string(UiTheme.font("bungee"), label_at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.ACCENT)
