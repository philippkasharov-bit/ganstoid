## UI6: top-right clock and day, Zomboid-style (moodles hang below it).
class_name ClockBox
extends PanelContainer

var _world: World
var _time := UiTheme.label("", 20, UiTheme.TEXT)
var _day := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DIM)
var _speed := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.ACCENT)   # Z2: "Paused" / ">> 20x"
var _driver: Node

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiTheme.window_box())
	_time.add_theme_font_size_override("font_size", 12)
	_time.add_theme_color_override("font_color", UiTheme.TEXT)   # UI21: same white as the status card
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_time)
	box.add_child(_day)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_speed)

func _process(_delta: float) -> void:
	if _world == null:
		return
	visible = GameRules.of(_world) != null
	var hours := SimClock.day_fraction(_world.tick) * 24.0
	_time.text = "Day %d  ·  %02d:%02d" % [SimClock.day_number(_world.tick), int(hours), int(fmod(hours, 1.0) * 60.0)]
	_day.text = SimClock.year_month(_world.tick)   # T1: counted from the start of this life
	if _driver != null:
		_speed.text = speed_text(_driver.paused, _driver.speed, _driver.slowed_because)
		_speed.visible = _speed.text != ""
	position = Vector2(get_viewport_rect().size.x - size.x - UiTheme.MARGIN, UiTheme.MARGIN)

## Z2: what the clock says about time: paused, fast, or why it slowed back down.
static func speed_text(paused: bool, speed: int, slowed: String) -> String:
	if paused:
		return "Paused  (F3 to go on)"
	if speed > 1:
		return ">> %dx" % speed
	return "Back to 1x: %s" % slowed if slowed != "" else ""
