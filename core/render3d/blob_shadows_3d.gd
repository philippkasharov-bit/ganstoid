## A2a: a soft dark patch on the ground under each person, car, tree,
## palm and bush, so they stand on the street instead of floating (Phil
## okayed these; there are still no real-time shadows). One flat plane
## per thing in a MultiMesh, darkening what is under it, fading out at
## its rim. The material is made once on the main thread (prime).
class_name BlobShadows3D
extends RefCounted

const Y := 0.065            # just above the road (0.04) and the paint
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying float dark;
varying float rad;
void vertex() {
	dark = INSTANCE_CUSTOM.r;
	rad = length(VERTEX.xz) * 2.0;   // 0 in the middle, 1 at the rim
}
void fragment() {
	ALBEDO = vec3(0.0);
	float f = 1.0 - smoothstep(0.0, 1.0, rad);
	ALPHA = dark * 0.95 * f * f;   // PF2: one disc faded per pixel (Forward+); was fourteen stacked discs, 280 triangles each
}
"""
const RING := 24

static var _material: ShaderMaterial
static var _plane: ArrayMesh

## The shared material and plane (call once from GameView3D.setup).
static func prime() -> void:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
		_plane = _disc()

## A unit patch: one disc of radius 0.5; the shader fades it from the middle out.
static func _disc() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in RING:
		st.set_normal(Vector3.UP)
		for p in [Vector2.ZERO, Vector2.from_angle(TAU * k / RING) * 0.5, Vector2.from_angle(TAU * (k + 1) / RING) * 0.5]:
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	return st.commit()

## A layer of up to `count` patches.
static func layer(count: int) -> MultiMeshInstance3D:
	prime()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _plane
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Patch `i`: centred on 3D x/z `at`, `size` metres (x along `angle`), `dark` 0..1.
static func place(mi: MultiMeshInstance3D, i: int, at: Vector3, size: Vector2, angle: float, dark: float) -> void:
	var basis := Basis(Vector3.UP, -angle).scaled_local(Vector3(size.x, 1.0, size.y))
	mi.multimesh.set_instance_transform(i, Transform3D(basis, Vector3(at.x, Y, at.z)))
	mi.multimesh.set_instance_custom_data(i, Color(dark, 0, 0, 0))
