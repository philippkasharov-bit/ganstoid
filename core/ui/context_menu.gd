## UI4: Zomboid-style right-click menu: a plain list at the cursor, rows
## light up on hover, greyed rows show why they cannot be picked.
class_name ContextMenu
extends PanelContainer

signal picked(index: int)

var _list := VBoxContainer.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG))
	_list.add_theme_constant_override("separation", 0)
	add_child(_list)
	visible = false

## options: Array of {"text": String, "enabled": bool, "why": String}
func open_at(screen_pos: Vector2, options: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in options.size():
		_list.add_child(_row(i, options[i]))
	visible = true
	reset_size()
	var screen := get_viewport_rect().size
	position = screen_pos.clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))

func _row(index: int, option: Dictionary) -> Button:
	var enabled: bool = option.get("enabled", true)
	var b := Button.new()
	b.text = option["text"] if enabled else "%s  (%s)" % [option["text"], option.get("why", "")]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(180, UiTheme.ROW_H)
	b.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	b.add_theme_color_override("font_disabled_color", UiTheme.DIM)
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BG_ROW_HOVER, Color.TRANSPARENT, 0))
	b.pressed.connect(func() -> void:
		visible = false
		picked.emit(index))
	return b

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var click: bool = event is InputEventMouseButton and event.pressed
	if (click and not get_global_rect().has_point(event.position)) or event.is_action_pressed("ui_cancel"):
		visible = false
