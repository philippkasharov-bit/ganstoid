## M2/M3: the 90s sedan (assets/models/car_90s_sedan.glb: Tripo, from a Magnific reference image, cleaned in Blender) taken
## apart for CarRig3D's MultiMeshes: the body mesh (its Body_Paint surface
## takes each car's paint from the instance colour; trim, glass, chrome and
## lamps keep their own materials), one wheel mesh, and where the four
## wheels sit. Loaded once, on the main thread (CarRig3D is made there).
class_name CarModel3D
extends RefCounted

const PATH := "res://assets/models/car_90s_sedan.glb"
const LENGTH := 4.9   # M3: the Tripo sedan's body, which each car is stretched from
const WIDTH := 2.0
const PAINT := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
vec3 lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
void fragment() {
	vec4 t = texture(tex, UV);
	float red = smoothstep(0.1, 0.28, t.r - max(t.g, t.b));   // the model's red paint (not chrome, glass, tyres or amber lamps)
	float shade = dot(t.rgb, vec3(0.3, 0.59, 0.11)) / 0.16;   // its light and dark, kept
	ALBEDO = mix(t.rgb, lin(COLOR.rgb) * clamp(shade, 0.35, 1.4), red);
	ROUGHNESS = mix(0.7, 0.35, red);
	METALLIC = 0.15 * red;
}
"""

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

## A copy of the body whose Body_Paint surface repaints the model's red with each copy's instance colour.
static func _painted(mesh: Mesh) -> Mesh:
	var copy: ArrayMesh = mesh.duplicate()
	var shader := Shader.new()
	shader.code = PAINT
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s) as StandardMaterial3D
		if mat != null and (mat.resource_name == "Body_Paint" or mat.albedo_texture != null):   # the Tripo body has one textured material
			var paint := ShaderMaterial.new()
			paint.shader = shader
			paint.set_shader_parameter("tex", mat.albedo_texture)
			copy.surface_set_material(s, paint)
	return copy
