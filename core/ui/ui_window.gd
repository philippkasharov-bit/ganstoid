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
	body.add_theme_constant_override("separation", UiTheme.SPACE)
	pad.add_child(body)
	column.add_child(pad)
	visibility_changed.connect(_animate_open)
	# UI20: no tape or stickers; _add_decor stays for a skin that wants them

func _build_header(title: String) -> PanelContainer:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box())
	header.custom_minimum_size.y = UiTheme.HEADER_H
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	header.add_child(row)
	_title = UiTheme.title_label(title.to_upper())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)
	row.add_child(_close_button())
	header.gui_input.connect(_on_header_input)
	return header

## UI25: a drawn X (no letter), dim until hovered, red on hover.
func _close_button() -> Button:
	var close := Button.new()
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(UiTheme.HEADER_H, UiTheme.HEADER_H)
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(close_window)
	close.draw.connect(func() -> void:
		var c := close.size * 0.5
		var col := UiTheme.BAD if close.is_hovered() else UiTheme.DIM
		close.draw_line(c - Vector2(4, 4), c + Vector2(4, 4), col, 1.5, true)
		close.draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), col, 1.5, true))
	close.mouse_entered.connect(close.queue_redraw)
	close.mouse_exited.connect(close.queue_redraw)
	return close

## UI25: windows fade and settle in (120 ms), like a real game's panels.
func _animate_open() -> void:
	if not visible or not is_inside_tree():
		return
	_keep_on_screen.call_deferred()   # UI26: never opens half off a small screen
	pivot_offset = size * 0.5
	modulate.a = 0.0
	scale = Vector2.ONE * 0.97
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.12)
	t.tween_property(self, "scale", Vector2.ONE, 0.12)

func _keep_on_screen() -> void:
	var screen := get_viewport_rect().size
	position = position.clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))

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

## UI18: masking tape on the top corners and one sticker, picked from the
## window id so each page keeps its own look. Drawn straight onto the page
## (a container would stretch child decals), so it never takes the mouse.
const STICKERS := ["boombox", "fireball", "spraycan", "cassette", "sneaker", "buckethat", "dollar_star", "eyeball", "bolt"]
const TAPE_H := 12.0
const STICKER_H := 40.0

var _decor: Array = []   # [texture, centre offset from a corner, corner (0 top-left .. 2 bottom-right), height, angle]

func _add_decor(id: String) -> void:
	var tape := _art("marker/tape")
	if tape != null:
		_decor.append([tape, Vector2(4, 2), 0, TAPE_H, -35.0])
		_decor.append([tape, Vector2(-4, 2), 1, TAPE_H, 33.0])
	var pick: int = absi(id.hash())
	var sticker := _art("stickers/" + STICKERS[pick % STICKERS.size()])
	if sticker != null:
		_decor.append([sticker, Vector2(-14, -10), 2, STICKER_H, -14.0 + float(pick % 28)])
	var layer := Node2D.new()   # not a Control, so the container leaves it alone; draws over the page
	layer.name = "Decor"
	add_child(layer)
	layer.draw.connect(func() -> void: _draw_decor(layer))
	resized.connect(layer.queue_redraw)

static func _art(name: String) -> Texture2D:
	var path := UiTheme.STREET + name + ".png"
	return load(path) if ResourceLoader.exists(path) else null

func _draw_decor(layer: Node2D) -> void:
	var corners := [Vector2.ZERO, Vector2(size.x, 0), size]
	for d in _decor:
		var tex: Texture2D = d[0]
		var h: float = d[3]
		var w := h * tex.get_width() / tex.get_height()
		layer.draw_set_transform(corners[d[2]] + d[1], deg_to_rad(d[4]), Vector2.ONE)
		layer.draw_texture_rect(tex, Rect2(Vector2(-w, -h) * 0.5, Vector2(w, h)), false)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
