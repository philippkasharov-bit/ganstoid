## R3D0-R3D12: the 3D look test (debug/shot_3d.gd): the real sim (no
## new-game panel) under GameView3D, round the spawn, with a smaller
## district so it builds fast.
extends GameView3D

const RADIUS_M := 110.0

@export var live_sim := true
var driver: Node

func _init() -> void:
	radius_m = RADIUS_M

func _ready() -> void:
	Engine.set_meta("skip_new_game", true)
	driver = load("res://core/world_driver.gd").new()
	add_child(driver)
	setup(driver.world, driver.city, driver.city.spawn)
	ScreenMap.use_3d(rig.camera, centre)
