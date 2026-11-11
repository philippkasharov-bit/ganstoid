## O1: new game: pick how hard, then how you want to play. The world waits.
class_name NewGamePanel
extends UiPanel

var _driver: Node
var _difficulty := -1

func open(driver: Node) -> void:
	_driver = driver
	setup(driver.world, Vector2(60, 60))
	custom_minimum_size = Vector2(760, 0)

func refresh() -> void:
	if _driver == null or not _driver.choosing:
		visible = false
		return
	var view := get_viewport_rect().size
	position = ((view - size) * 0.5).floor()
	var rows: Array = []
	if _difficulty < 0:
		for i in 3:
			rows.append([str(i + 1), "%s — %s" % [GameRules.DIFFICULTIES[i], GameRules.DIFFICULTY_TEXT[i]], ""])
		show_panel("New life · how hard?", rows, "1-3 choose")
	else:
		for i in 3:
			rows.append([str(i + 1), "%s — %s" % [GameRules.STYLES[i], GameRules.STYLE_TEXT[i]], ""])
		show_panel("New life · how do you want to play?", rows, "1-3 choose    (%s)" % GameRules.DIFFICULTIES[_difficulty])

func _unhandled_input(event: InputEvent) -> void:
	if _driver == null or not _driver.choosing or not (event is InputEventKey) or not event.pressed:
		return
	var k: int = event.physical_keycode - KEY_1
	if k < 0 or k > 2:
		return
	if _difficulty < 0:
		_difficulty = k
	else:
		_driver.choose(_difficulty, k)
	get_viewport().set_input_as_handled()
