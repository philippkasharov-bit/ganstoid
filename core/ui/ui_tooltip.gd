## UI4: the item/thing tooltip: a title, coloured stat lines and a dim
## description, drawn beside the mouse and kept on screen.
class_name UiTooltip
extends PanelContainer

const OFFSET := Vector2(16, 16)

var _box := VBoxContainer.new()
var _paper := false

## Light UI colours are unreadable on paper: swap them for ink.
func _ink(colour: Color) -> Color:
	if not _paper:
		return colour
	if colour == UiTheme.TEXT:
		return UiTheme.INK
	if colour == UiTheme.DIM:
		return Color(0.3, 0.28, 0.25)
	return colour.darkened(0.35)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrap := UiTheme.texture_box("book/scrap", Color.WHITE, 8)
	if scrap != null:   # UI18: a torn notebook scrap, dark ink
		scrap.texture_margin_left = 12
		scrap.texture_margin_right = 12
		scrap.texture_margin_top = 12
		scrap.texture_margin_bottom = 12
		scrap.content_margin_left = 12
		scrap.content_margin_right = 12
		_paper = true
	add_theme_stylebox_override("panel", scrap if scrap != null else UiTheme.box(UiTheme.BG_HEADER))
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	visible = false

## lines: Array of [text, colour]
func show_at(screen_pos: Vector2, title: String, lines: Array, note: String = "") -> void:
	for c in _box.get_children():
		_box.remove_child(c)   # now, not at frame end, so the size below fits the new lines
		c.queue_free()
	var head := UiTheme.label(title, UiTheme.FONT_BODY, UiTheme.INK if _paper else UiTheme.ACCENT)
	head.add_theme_font_override("font", UiTheme.font("marker"))
	_box.add_child(head)
	for line in lines:
		_box.add_child(UiTheme.label(line[0], UiTheme.FONT_SMALL, _ink(line[1])))
	if note != "":
		var n := UiTheme.label(note, UiTheme.FONT_SMALL, _ink(UiTheme.DIM))
		n.autowrap_mode = TextServer.AUTOWRAP_WORD
		n.custom_minimum_size.x = 170
		_box.add_child(n)
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

func hide_tip() -> void:
	visible = false
