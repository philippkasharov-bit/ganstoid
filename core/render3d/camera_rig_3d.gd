## R3D6: Zomboid's camera in 3D: orthographic, looking 30 degrees down,
## following the player. Mouse wheel and +/- zoom smoothly; "," and "."
## turn the view 90 degrees with a short eased turn (Q and E are taken by
## the game). The rig is a pivot on the player; the camera sits far back
## along its view line so nothing on screen is ever behind it.
class_name CameraRig3D
extends Node3D

const PITCH_DEG := -30.0
const START_YAW_DEG := 45.0
const BACK_M := 1500.0
const SIZE_MIN := 12.0         # metres of view height: close street level
const SIZE_MAX := 160.0        # a few blocks
const START_SIZE := 40.0
const ZOOM_STEP := 1.15
const EASE := 10.0             # how fast zoom, turn and follow settle (per second)

var world: World
var follow: RenderSync3D        # Z-feel: the camera sits on where the player is drawn
var origin := Vector2.ZERO     # map point at 3D (0, 0, 0)
var camera := Camera3D.new()
var yaw_deg := START_YAW_DEG
var target_yaw_deg := START_YAW_DEG
var target_size := START_SIZE

func _ready() -> void:
	process_priority = 10   # after RenderSync3D: follow this frame's player, not last frame's
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = START_SIZE
	camera.near = 1.0
	camera.far = 4000.0
	camera.position = Vector3(0, 0, BACK_M)
	add_child(camera)
	camera.current = true
	_apply_turn()

func _process(delta: float) -> void:
	var k := minf(1.0, delta * EASE)
	yaw_deg = lerpf(yaw_deg, target_yaw_deg, k)
	camera.size = lerpf(camera.size, target_size, k)
	_apply_turn()
	if follow != null and follow.player_shown != Vector2.INF:
		var p := follow.player_shown - origin
		position = Vector3(p.x, 0, p.y)   # Z-feel: locked on you, as in Zomboid (no lag, no drift)

func _apply_turn() -> void:
	rotation_degrees = Vector3(PITCH_DEG, yaw_deg, 0)

## Snap the view straight onto a map point (no easing): a teleport or a new game.
func look_at_map(p: Vector2) -> void:
	position = Vector3(p.x - origin.x, 0, p.y - origin.y)

func zoom_by(factor: float) -> void:
	target_size = clampf(target_size / factor, SIZE_MIN, SIZE_MAX)

func turn(quarters: int) -> void:
	target_yaw_deg += 90.0 * quarters

## Map direction (x east, y south) of screen-up for this view: WASD will walk by it.
func screen_up() -> Vector2:
	var f := -global_basis.z
	return Vector2(f.x, f.z).normalized()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / ZOOM_STEP)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD: zoom_by(1.25)
			KEY_MINUS, KEY_KP_SUBTRACT: zoom_by(0.8)
			KEY_COMMA: turn(-1)
			KEY_PERIOD: turn(1)
