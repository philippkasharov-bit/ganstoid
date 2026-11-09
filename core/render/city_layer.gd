## MG1c: the real city map under the game (CityRenderer fed from WorldDriver's
## CityData). Switches to the night palette with the game clock (dusk 19:00,
## dawn 06:00); the map only redraws when that flips.
extends CityRenderer

@export var world_driver_path: NodePath

const DUSK := 19.0 / 24.0
const DAWN := 6.0 / 24.0

var _driver: Node

func _ready() -> void:
	_driver = get_node(world_driver_path)
	city = _driver.city
	show_markers = false

func _process(_delta: float) -> void:
	var f := SimClock.day_fraction(_driver.world.tick)
	var is_night := f >= DUSK or f < DAWN
	if is_night != night:
		night = is_night
