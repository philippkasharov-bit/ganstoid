## UI6: top-right clock and day, Zomboid-style (moodles hang below it).
class_name ClockBox
extends PanelContainer

var _world: World
var _time := UiTheme.label("", 20, UiTheme.TEXT)
var _day := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DIM)

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_time)
	box.add_child(_day)

func _process(_delta: float) -> void:
	if _world == null:
		return
	visible = GameRules.of(_world) != null
	var hours := SimClock.day_fraction(_world.tick) * 24.0
	_time.text = "Day %d  ·  %02d:%02d" % [SimClock.day_number(_world.tick), int(hours), int(fmod(hours, 1.0) * 60.0)]
	_day.text = SimClock.year_month(_world.tick)   # T1: counted from the start of this life
	position = Vector2(get_viewport_rect().size.x - size.x - 12, 10)
