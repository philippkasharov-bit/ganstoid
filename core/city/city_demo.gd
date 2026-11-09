## City demo scene (C1-C3e): walk the real city. Pedestrians by type: blue civilians keep
## to sidewalks/crosswalks, purple dark-route NPCs take alleys, orange locals cut through gaps.
## Arrows/WASD move, Shift run, Space sprint (demo-only fast travel), N night, M markers, +/- or wheel zoom.
## Command line (after "--"): --shot=<png> saves one frame and quits; --night starts at night.
extends Node2D

const WALK := 8.0      # demo speeds (m/s), not final game speeds
const RUN := 25.0
const SPRINT := 120.0  # demo fast travel, not a game mechanic
const ZOOM_MIN := 0.12
const ZOOM_MAX := 4.0

var city: CityData
var renderer: CityRenderer
var collision: CityCollision
var nav: CityNav          # full layer: player and locals (know every shortcut)
var public_nav: CityNav   # civilians
var dark_nav: CityNav     # dark-route NPCs: public ground, alleys at normal cost
var walkers: DemoWalkers
var nav_focus := Vector2.ZERO
var player_path := PackedVector2Array()
var player_pos := Vector2.ZERO
var camera: Camera2D
var player_dot: Node2D
var hint: Label

func _ready() -> void:
	city = CityData.load_file()
	if city == null:
		return
	renderer = CityRenderer.new()
	renderer.city = city
	add_child(renderer)
	collision = CityCollision.new(city)
	player_pos = _free_spot(city.spawn)
	nav = CityNav.new(player_pos)
	public_nav = CityNav.new(player_pos, 700.0, "public")
	dark_nav = CityNav.new(player_pos, 700.0, "public")
	nav_focus = player_pos
	walkers = DemoWalkers.new()
	walkers.setup(public_nav, dark_nav, nav)
	add_child(walkers)   # walkers spawn once the navmeshes have synced (see _process)
	player_dot = _make_player_dot()
	add_child(player_dot)
	camera = Camera2D.new()
	camera.zoom = Vector2(0.6, 0.6)
	add_child(camera)
	_make_hud()
	_apply_cmdline()

func _process(delta: float) -> void:
	if city == null:
		return
	var dir := _move_input()
	var speed := SPRINT if Input.is_physical_key_pressed(KEY_SPACE) else (RUN if Input.is_physical_key_pressed(KEY_SHIFT) else WALK)
	var step := dir * speed * delta
	if dir != Vector2.ZERO:
		player_path = PackedVector2Array()   # keys override click-to-walk
	elif player_path.size() > 0:
		step = player_pos.direction_to(player_path[0]) * minf(RUN * delta, player_pos.distance_to(player_path[0]))
		if player_pos.distance_to(player_path[0]) < 0.5:
			player_path.remove_at(0)
	player_pos = (collision.slide(player_pos, step) if speed < SPRINT else player_pos + step).clamp(Vector2.ZERO, Vector2(city.size_m, city.size_m))
	if player_pos.distance_to(nav_focus) > 350.0:   # stream nav tiles around the player
		nav_focus = player_pos
		for n in [nav, public_nav, dark_nav]:
			n.focus(player_pos)
	if walkers.walkers.is_empty():
		if nav.is_ready() and public_nav.is_ready() and dark_nav.is_ready():
			walkers.spawn(player_pos, 60)
	else:
		walkers.advance(delta)
	player_dot.position = player_pos
	camera.position = player_pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_N:
				renderer.night = not renderer.night
				walkers.night = renderer.night
			KEY_M: renderer.show_markers = not renderer.show_markers
			KEY_P: renderer.show_public = not renderer.show_public
			KEY_EQUAL, KEY_KP_ADD: _zoom(1.25)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom(0.8)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:   # click-to-walk along a real path
			player_path = nav.path(player_pos, get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.87)

## Nearest street point to `p` that is outside every building.
func _free_spot(p: Vector2) -> Vector2:
	var best := p
	var best_d := INF
	for road in city.roads_of("res"):
		for q in road["pts"]:
			var d: float = q.distance_squared_to(p)
			if d < best_d and not collision.blocked(q):
				best_d = d
				best = q
	return best

func _move_input() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A): d.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D): d.x += 1
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W): d.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S): d.y += 1
	return d.normalized()

func _zoom(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

func _make_player_dot() -> Node2D:
	var dot := Node2D.new()
	dot.draw.connect(func() -> void:
		dot.draw_circle(Vector2.ZERO, 14.0, Color("1b1b1b"))
		dot.draw_circle(Vector2.ZERO, 10.0, Color("ff3b6b")))
	return dot

func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hint = Label.new()
	hint.position = Vector2(12, 8)
	hint.add_theme_color_override("font_color", Color.WHITE)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.text = "City demo (C3e)  |  Blue civilians (sidewalks)  Purple dark-route (alleys)  Orange locals (shortcuts)\nArrows/WASD move  Right-click walk there  Shift run  Space fast-travel  |  N night  M markers  P public paths  +/- or wheel zoom"
	layer.add_child(hint)

func _apply_cmdline() -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--night":
			renderer.night = true
			walkers.night = true
		elif arg == "--public":
			renderer.show_public = true
		elif arg.begins_with("--shot="):
			shot = arg.substr(7)
		elif arg.begins_with("--sim="):
			_sim_seconds = float(arg.substr(6))
		elif arg.begins_with("--zoom="):
			camera.zoom = Vector2.ONE * float(arg.substr(7))
		elif arg.begins_with("--at="):
			var xy := arg.substr(5).split(",")
			player_pos = Vector2(float(xy[0]), float(xy[1]))
	if shot != "":
		_save_shot(shot)

var _sim_seconds := 0.0

func _save_shot(path: String) -> void:
	while walkers.walkers.is_empty():   # wait for the navmesh sync and the walkers
		await get_tree().process_frame
	for k in int(_sim_seconds * 10):
		walkers.advance(0.1)
	_process(0.0)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
