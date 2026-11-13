## Z-feel validator: a bot plays the real game in 3D for a while (walking
## with WASD, the bag open and shut, right-click menus, E menus, crouching,
## the car door, camera turns and zoom, the turf map and back, F9 to 2D and
## back, fast-forward) and the game must stay sound: the player moves in 3D
## with the bag open, the camera stays on the player, every switch lands in
## the right view, and no script errors are logged.
extends SceneTree

var _w: World
var _me: NPCData
var _view: GameView3D

func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))   # a fresh life, and none left behind
	Engine.set_meta("skip_new_game", true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_w = main.get_node("WorldDriver").world
	_view = main.get_node("View3D")
	while SimNav.active == null or not SimNav.active.is_ready():
		await process_frame
	_me = _w.entities[&"player"].get_component(ComponentNames.NPC)
	var st: PlayerStateData = _w.entities[&"player"].get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	var moved := await _walk(KEY_W, 40)
	await _tap(KEY_I)
	var with_bag := await _walk(KEY_D, 40)
	ok = ok and moved > 0.5 and with_bag > 0.5 and st.inventory_open
	await _tap(KEY_I)
	for key in [KEY_C, KEY_C, KEY_E, KEY_ESCAPE, KEY_F, KEY_COMMA, KEY_PERIOD, KEY_EQUAL, KEY_MINUS, KEY_F4, KEY_F3]:
		await _tap(key)
		await _walk(KEY_A, 10)
	await _click(MOUSE_BUTTON_RIGHT)
	await _walk(KEY_S, 20)
	var on_player := _view.rig.position.distance_to(Vector3(_me.position.x - _view.centre.x, 0, _me.position.y - _view.centre.y)) < 1.5
	await _tap(KEY_U)
	var map_2d := not _view.on and not ScreenMap.is_3d()
	for i in 2:
		await _tap(KEY_U)   # money, then off: back to 3D
	await process_frame
	await process_frame
	var back_3d := _view.on and ScreenMap.is_3d()
	await _tap(KEY_F9)
	var flipped := not _view.on
	await _tap(KEY_F9)
	print("walked %.1f m, %.1f m with the bag open; camera on you %s; U map in 2D %s, back to 3D %s; F9 %s" % [moved, with_bag, on_player, map_2d, back_3d, flipped and _view.on])
	ok = ok and on_player and map_2d and back_3d and flipped and _view.on
	print("PLAY_3D_VERIFY: %s" % ("PASS" if ok else "FAIL - the 3D game does not play right"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))
	quit(0 if ok else 1)

func _walk(key: Key, frames: int) -> float:
	var from := _me.position
	_key(key, true)
	for i in frames:
		await physics_frame
	_key(key, false)
	await physics_frame
	return _me.position.distance_to(from)

func _tap(key: Key) -> void:
	_key(key, true)
	await process_frame
	await physics_frame
	_key(key, false)
	await process_frame
	await physics_frame

func _key(key: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = down
	Input.parse_input_event(ev)

func _click(button: MouseButton) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = down
		ev.position = root.get_visible_rect().size * 0.5 + Vector2(40, 10)
		Input.parse_input_event(ev)
		await physics_frame
