## BUG-16 validator: the player figure stays in its ring. The model's Walk and
## Idle clips must keep the hips within HIPS_M of the figure's origin
## (sideways and forward); the baked gangster walk had them ~1.3 m ahead.
extends SceneTree

const HIPS_M := 0.15

func _initialize() -> void:
	var pm := PlayerModel3D.new()
	root.add_child(pm)
	await process_frame
	var ok := pm.usable()
	var ap: AnimationPlayer = pm.find_child("AnimationPlayer", true, false)
	var arm: Node3D = pm.find_child("Armature", true, false)
	var unit: float = arm.scale.x if arm != null else 1.0
	for name in ["Walk", "Idle"]:
		var a := ap.get_animation(name) if ap != null else null
		var t := a.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_POSITION_3D) if a != null else -1
		var far := 0.0
		for k in (a.track_get_key_count(t) if t >= 0 else 0):
			var v: Vector3 = a.track_get_key_value(t, k)
			far = maxf(far, Vector2(v.x, v.z).length() * unit)
		print("%s: hips at most %.2f m from the feet" % [name, far])
		ok = ok and t >= 0 and far <= HIPS_M
	pm.queue_free()
	print("PLAYER_MODEL_VERIFY: PASS" if ok else "PLAYER_MODEL_VERIFY: FAIL - the figure leaves its ring")
	quit(0 if ok else 1)
