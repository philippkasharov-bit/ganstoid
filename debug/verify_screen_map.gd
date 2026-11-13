## R3D12 validator: the screen-to-map bridge in 3D. A map point projected to
## the screen and cast back lands where it started (any camera turn), and
## WASD follows the screen: W walks the way the camera looks, D to screen
## right; in 2D nothing turns.
extends SceneTree

func _initialize() -> void:
	var ok := absf(ScreenMap.move_turn()) < 0.0001   # 2D: no camera registered
	var rig := CameraRig3D.new()
	rig.origin = Vector2(5000, 3000)
	root.add_child(rig)
	await process_frame
	for quarters in [0, 1]:
		rig.turn(quarters)
		rig.yaw_deg = rig.target_yaw_deg
		rig._apply_turn()
		await process_frame
		var p := Vector2(5012.0, 2991.0)
		var back := ScreenMap.to_map(root, ScreenMap.to_screen(root, p))
		var w := Vector2(0, -1).rotated(ScreenMap.move_turn())
		var f := -rig.camera.global_basis.z
		var d := Vector2(1, 0).rotated(ScreenMap.move_turn())
		var right := rig.camera.global_basis.x
		print("turn %d: round trip off %.3f m; W vs view %.3f; D vs screen right %.3f" % [quarters, back.distance_to(p), w.dot(Vector2(f.x, f.z).normalized()), d.dot(Vector2(right.x, right.z).normalized())])
		ok = ok and back.distance_to(p) < 0.05 and w.dot(Vector2(f.x, f.z).normalized()) > 0.99 and d.dot(Vector2(right.x, right.z).normalized()) > 0.99
	print("SCREEN_MAP_VERIFY: %s" % ("PASS" if ok else "FAIL - screen and map disagree"))
	quit(0 if ok else 1)
