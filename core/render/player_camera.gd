## MG1c: camera that follows the player around the real city (metres).
## Mouse wheel / +/- zoom between ZOOM_MIN and ZOOM_MAX pixels per metre.
extends Camera2D

@export var world_driver_path: NodePath

const ZOOM_MIN := 0.5
const ZOOM_MAX := 30.0
const START_ZOOM := 12.0   # ~100 m across the screen: street level, walking is visible

var _world: World

func _ready() -> void:
	_world = get_node(world_driver_path).world
	zoom = Vector2.ONE * START_ZOOM

func _process(_delta: float) -> void:
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null:
		position = player.get_component(ComponentNames.NPC).position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.15)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]:
			_zoom_by(1.25)
		elif event.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom_by(0.8)

func _zoom_by(factor: float) -> void:
	zoom = Vector2.ONE * clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
