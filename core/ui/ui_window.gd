## UI4: base for every movable panel: title bar you drag, close button,
## clamped to the screen. Content goes in `body`. Position is kept per
## window id for the session so panels reopen where the player left them.
class_name UiWindow
extends PanelContainer

signal closed

static var _positions: Dictionary = {}

var window_id := ""
var body := VBoxContainer.new()
var _title: Label
var _dragging := false
var _grab := Vector2.ZERO

func setup_window(id: String, title: String, at: Vector2, min_size: Vector2) -> void:
	window_id = id
	position = _positions.get(id, at)
	custom_minimum_size = min_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.window_box())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	column.add_child(_build_header(title))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, UiTheme.PAD)
	body.add_theme_constant_override("separation", 4)
	pad.add_child(body)
	column.add_child(pad)

func _build_header(title: String) -> PanelContainer:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box())
	header.custom_minimum_size.y = UiTheme.HEADER_H + 4
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	header.add_child(row)
	_title = UiTheme.title_label(title.to_upper())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)
	var close := Button.new()
	close.text = "x"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_override("font", UiTheme.font("marker"))
	close.add_theme_color_override("font_color", UiTheme.INK)
	close.add_theme_color_override("font_hover_color", UiTheme.BAD)
	close.tooltip_text = "Close"
	close.pressed.connect(close_window)
	row.add_child(close)
	header.gui_input.connect(_on_header_input)
	return header

func set_title(title: String) -> void:
	_title.text = title.to_upper()

func close_window() -> void:
	visible = false
	closed.emit()

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_grab = get_global_mouse_position() - position
	elif event is InputEventMouseMotion and _dragging:
		move_to(get_global_mouse_position() - _grab)

func move_to(at: Vector2) -> void:
	var screen := get_viewport_rect().size
	position = at.clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))
	_positions[window_id] = position
