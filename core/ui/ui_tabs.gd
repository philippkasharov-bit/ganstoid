## UI19: Zomboid-style tabs along the top of a window. The picked tab sits on
## a white marker swipe in ink; the rest are dim marker text. 1..n tabs, one
## page each; only the picked page is shown.
class_name UiTabs
extends VBoxContainer

signal changed(index: int)

var _bar := HBoxContainer.new()
var _pages: Array[Control] = []
var _buttons: Array[Button] = []
var current := 0

func _init() -> void:
	add_theme_constant_override("separation", 4)
	_bar.add_theme_constant_override("separation", 2)
	add_child(_bar)

func add_tab(title: String, page: Control) -> void:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 20)
	b.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	var index := _pages.size()
	b.pressed.connect(func() -> void: pick(index))
	_bar.add_child(b)
	_buttons.append(b)
	_pages.append(page)
	add_child(page)
	pick(current)

func pick(index: int) -> void:
	current = clampi(index, 0, _pages.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == current
		_style(_buttons[i], i == current)
	changed.emit(current)

static func _style(b: Button, on: bool) -> void:
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 10
	flat.content_margin_right = 10
	var look: StyleBox = flat
	if on:
		var under := StyleBoxFlat.new()
		under.bg_color = Color.TRANSPARENT
		under.border_width_bottom = 2
		under.border_color = UiTheme.ACCENT
		under.content_margin_left = 10
		under.content_margin_right = 10
		look = under
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, look)
	b.add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.DIM)
	b.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
