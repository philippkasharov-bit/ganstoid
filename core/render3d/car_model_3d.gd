## M2: the 90s sedan made in Blender (assets/models/car_90s_sedan.glb) taken
## apart for CarRig3D's MultiMeshes: the body mesh (its Body_Paint surface
## takes each car's paint from the instance colour; trim, glass, chrome and
## lamps keep their own materials), one wheel mesh, and where the four
## wheels sit. Loaded once, on the main thread (CarRig3D is made there).
class_name CarModel3D
extends RefCounted

const PATH := "res://assets/models/car_90s_sedan.glb"
const LENGTH := 4.5   # the model's body, which each car is stretched from
const WIDTH := 1.8

static var _loaded := false
static var body: Mesh
static var wheel: Mesh
static var hubs: Array[Vector3] = []   # FL, FR, RL, RR in the model's space

## True when the model is there to use.
static func ready() -> bool:
	if not _loaded:
		_loaded = true
		_load()
	return body != null and wheel != null and hubs.size() == 4

static func _load() -> void:
	if not ResourceLoader.exists(PATH):
		return
	var scene: Node = (load(PATH) as PackedScene).instantiate()
	var shell: MeshInstance3D = scene.find_child("car_body", true, false)
	if shell != null:
		body = _painted(shell.mesh)
		for name in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]:
			var w: MeshInstance3D = shell.find_child(name, true, false)
			if w != null:
				wheel = w.mesh
				hubs.append(w.position)
	scene.free()

## A copy of the body whose Body_Paint surface is coloured by each copy's instance colour.
static func _painted(mesh: Mesh) -> Mesh:
	var copy: ArrayMesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s)
		if mat != null and mat.resource_name == "Body_Paint":
			var paint: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
			paint.albedo_color = Color.WHITE
			paint.vertex_color_use_as_albedo = true
			paint.vertex_color_is_srgb = true
			copy.surface_set_material(s, paint)
	return copy
