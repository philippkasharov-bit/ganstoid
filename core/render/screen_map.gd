## R3D12: the one bridge between the screen and the map, for whichever view
## is up. The 2D view uses the canvas transform; once a 3D camera registers
## (CameraRig3D) the mouse is cast onto the ground and map points are
## projected through it, and WASD turns with the camera so W is always
## "up the screen" (Zomboid walks diagonally across the map).
class_name ScreenMap
extends RefCounted

static var camera3d: Camera3D
static var origin := Vector2.ZERO   # map point at 3D (0, 0, 0)

static func use_3d(camera: Camera3D, map_origin: Vector2) -> void:
	camera3d = camera
	origin = map_origin

static func is_3d() -> bool:
	return camera3d != null and is_instance_valid(camera3d) and camera3d.is_inside_tree() and camera3d.current

## The map point under a screen position (the ground, in 3D).
static func to_map(vp: Viewport, screen: Vector2) -> Vector2:
	if not is_3d():
		return vp.get_canvas_transform().affine_inverse() * screen
	var from := camera3d.project_ray_origin(screen)
	var dir := camera3d.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return origin
	var hit := from + dir * (-from.y / dir.y)
	return Vector2(hit.x, hit.z) + origin

## Where a map point (lifted `lift_m` off the ground in 3D) is on screen.
static func to_screen(vp: Viewport, p: Vector2, lift_m: float = 0.0) -> Vector2:
	if not is_3d():
		return vp.get_canvas_transform() * p
	return camera3d.unproject_position(Vector3(p.x - origin.x, lift_m, p.y - origin.y))

## How far WASD turns: 0 in 2D; in 3D so screen-up walks the way the camera looks.
static func move_turn() -> float:
	if not is_3d():
		return 0.0
	var f := -camera3d.global_basis.z
	return Vector2(f.x, f.z).angle() + PI * 0.5

## Screen pixels per map metre at the ground (the zoom), in either view.
static func px_per_m(vp: Viewport) -> float:
	if not is_3d():
		return vp.get_canvas_transform().get_scale().x
	return vp.get_visible_rect().size.y / camera3d.size
