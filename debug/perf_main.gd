## Frame-cost probe for the game scene (not a check): loads scenes/main.tscn, waits
## for the streets, then reports frame time and draw load at several zooms.
## Run: godot --rendering-driver opengl3 --path . -s debug/perf_main.gd [-- --frames=120]
extends SceneTree

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run(main)

func _run(main: Node) -> void:
	var t0 := Time.get_ticks_msec()
	while SimNav.active == null or not SimNav.active.is_ready():
		await process_frame
	print("streets ready after %d ms; nodes %d" % [Time.get_ticks_msec() - t0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var cam: Camera2D = main.get_node("Camera2D")
	for zoom in [12.0, 5.0, 2.0, 0.6]:
		cam.zoom = Vector2.ONE * zoom
		for i in 10:
			await process_frame
		var worst := 0.0
		var total := 0.0
		var script_ms := 0.0
		var physics_ms := 0.0
		var frames := 90
		for i in frames:
			var t := Time.get_ticks_usec()
			await process_frame
			var ms := (Time.get_ticks_usec() - t) / 1000.0
			total += ms
			worst = maxf(worst, ms)
			script_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		print("zoom %4.1f px/m: frame %.1f ms avg, %.1f worst | scripts %.2f ms, sim %.2f ms | draw calls %d, primitives %d, canvas items drawn %d" % [
			zoom, total / frames, worst, script_ms / frames, physics_ms / frames,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	quit()
