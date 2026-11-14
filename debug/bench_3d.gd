## POP1 benchmark: the real 3D game (live sim, 1500 people) on THIS machine's GPU.
## Plays the city a while, then times 300 frames in each scene below with vsync
## off and prints CPU ms, GPU ms and FPS per scene, plus the GPU's name.
## The table also goes to user://bench_3d.txt.
##   godot --path . -s debug/bench_3d.gd            (windowed, 1920x1080)
extends SceneTree

const FRAMES := 300
const SCENES := [["street, day", 30.0, 13.0], ["default, day", 60.0, 13.0], ["wide, day", 120.0, 13.0], ["default, night", 60.0, 21.0]]

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	Engine.max_fps = 0
	var preview: Node3D = load("res://core/render3d/city3d_preview.gd").new()
	preview.live_sim = true
	root.add_child(preview)
	while SimNav.active == null or not SimNav.active.is_ready():
		await process_frame
	for i in 20 * Engine.physics_ticks_per_second:   # the morning gets going
		await physics_frame
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var lines := ["GPU: %s (%s)  %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), DisplayServer.window_get_size()]]
	lines.append("scene              CPU ms   GPU ms    FPS   worst ms   draw calls   triangles")
	for s in SCENES:
		lines.append(await _scene(preview, vp, s))
	var f := FileAccess.open("user://bench_3d.txt", FileAccess.WRITE)
	for l in lines:
		print(l)
		f.store_line(l)
	print("saved to " + ProjectSettings.globalize_path("user://bench_3d.txt"))
	quit()

func _scene(preview: Node3D, vp: RID, s: Array) -> String:
	preview.rig.target_size = s[1]
	preview.day_night.hour_override = s[2]
	for i in 60:
		await process_frame
	var cpu := 0.0
	var gpu := 0.0
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		var t := Time.get_ticks_usec()
		await process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / FRAMES
	return "%-16s %8.2f %8.2f %6.0f %10.1f %12d %11d" % [s[0], cpu / FRAMES, gpu / FRAMES, 1000.0 / wall, worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
