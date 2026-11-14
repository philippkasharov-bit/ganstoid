## G5: the Blender models up close (a car and a figure), to check them by eye.
## xvfb-run godot --path . --rendering-driver opengl3 -s debug/shot_models.gd -- --out=/tmp/models.png
extends SceneTree

func _init() -> void:
	var out := "/tmp/models.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var world := Node3D.new()
	root.add_child(world)
	var car := CarRig3D.new(1)
	var person := PersonRig3D.new(1)
	world.add_child(car)
	world.add_child(person)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("c8c4b8")
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.5
	cam.rotation_degrees = Vector3(-30, 45, 0)
	cam.position = Vector3(8, 6.5, 8)
	world.add_child(cam)
	cam.make_current()
	var data := VehicleData.new()
	data.position = Vector2(0, 0)
	data.length_m = 4.6
	data.width_m = 1.85
	car.place(0, &"car", data, Color("b0312a"), 1.0, false)
	car.set_count(1)
	person.place(0, Vector2(1.5, 2.2), 0.6, 0.3, 0.6, false, false, Color("e9e5dc"), Color("a8775a"))
	person.set_count(1)
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
