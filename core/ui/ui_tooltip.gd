## UI4: the item/thing tooltip: a title, coloured stat lines and a dim
## description, drawn beside the mouse and kept on screen.
class_name UiTooltip
extends PanelContainer

const OFFSET := Vector2(16, 16)

var _box := VBoxContainer.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100   # IT1: over every window, whichever window owns it
	add_theme_stylebox_override("panel", UiTheme.window_box(UiTheme.SPACE))   # UI25: the same card as every panel
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	visible = false

## lines: Array of [text, colour], or IT1 bar rows
## ["bar", label, fraction 0..1, colour, value text] (Zomboid's item card).
func show_at(screen_pos: Vector2, title: String, lines: Array, note: String = "", hints: Array = []) -> void:
	for c in _box.get_children():
		_box.remove_child(c)   # now, not at frame end, so the size below fits the new lines
		c.queue_free()
	var head := UiTheme.label(title, UiTheme.FONT_BODY, UiTheme.ACCENT)
	_box.add_child(head)
	for line in lines:
		_box.add_child(bar_row(line) if line.size() == 5 and line[0] == "bar" else UiTheme.label(line[0], UiTheme.FONT_SMALL, line[1]))
	if note != "":
		var n := UiTheme.label(note, UiTheme.FONT_SMALL, UiTheme.DIM)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD
		n.custom_minimum_size.x = 170
		_box.add_child(n)
	if not hints.is_empty():   # UI26: what you can do with it, as keycaps
		_box.add_child(UiTheme.divider())
		var k := UiTheme.key_hints(hints)
		k.custom_minimum_size.x = 170
		_box.add_child(k)
	visible = true
	size = Vector2.ZERO
	reset_size()
	var screen := get_viewport_rect().size
	var at := screen_pos + OFFSET
	if at.x + size.x > screen.x:
		at.x = screen_pos.x - OFFSET.x - size.x
	if at.y + size.y > screen.y:
		at.y = screen.y - size.y
	position = at.max(Vector2.ZERO)

const BAR_W := 80.0
const LABEL_W := 58.0

## "Damage  [=====     ]  55": label, a thin bar, the number.
static func bar_row(line: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := UiTheme.label(line[1], UiTheme.FONT_SMALL, UiTheme.DIM)
	l.custom_minimum_size.x = LABEL_W
	row.add_child(l)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(BAR_W, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var f: float = clampf(line[2], 0.0, 1.0)
	var col: Color = line[3]
	bar.draw.connect(func() -> void:
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(1, 1, 1, 0.08))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * f, bar.size.y)), col))
	row.add_child(bar)
	row.add_child(UiTheme.label(line[4], UiTheme.FONT_SMALL, UiTheme.TEXT))
	return row

func hide_tip() -> void:
	visible = false
