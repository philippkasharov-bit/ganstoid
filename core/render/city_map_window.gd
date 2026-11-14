## MP1: the Map window (N, or the side bar), Zomboid's map: the whole city with
## every shop and workshop on it (hover one for its trade and hours), your home
## and your businesses, and you. Tick boxes hide a kind; "Find me" re-centres.
class_name CityMapWindow
extends UiWindow

const ACTION := &"city_map"
const VIEW := Vector2(720, 520)

var _view := CityMapView.new()

func setup(world: World, city: CityData, at: Vector2) -> void:
	setup_window("city_map", "Map", at, Vector2(VIEW.x, 0))
	_view.world = world
	_view.city = city
	_view.custom_minimum_size = VIEW
	body.add_child(_bar())
	body.add_child(_view)
	CharacterWindow._bind(ACTION, KEY_N)   # M is muscle (crew); N for the map
	visible = false

## The legend: tick boxes in each marker's colour, and Find me.
func _bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE)
	row.add_child(_tick("Shops", CityMapView.SHOP, func(on: bool) -> void: _view.show_shops = on))
	row.add_child(_tick("Workshops", CityMapView.WORKSHOP, func(on: bool) -> void: _view.show_workshops = on))
	row.add_child(_tick("Yours", CityMapView.MINE, func(on: bool) -> void: _view.show_mine = on))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(UiTheme.label("wheel: zoom   drag: move   dim = closed", UiTheme.FONT_SMALL, UiTheme.DIM))
	var find := Button.new()
	find.text = "Find me"
	find.pressed.connect(_view.centre_on_player)
	row.add_child(find)
	return row

func _tick(text: String, col: Color, set_on: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = true
	c.add_theme_color_override("font_color", col)
	c.add_theme_color_override("font_pressed_color", col)
	c.toggled.connect(func(on: bool) -> void:
		set_on.call(on)
		_view._collect()
		_view.queue_redraw())
	return c

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION):
		visible = not visible
		if visible:
			_view.centre_on_player()
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		close_window()
