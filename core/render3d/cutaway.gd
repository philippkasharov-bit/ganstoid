## R3D4: you never lose sight of yourself behind a building. Walls, roofs and
## palms between the camera and the player are dithered out in a soft round
## hole along the line of sight (Zomboid fades what stands in front of you).
## Dithering keeps everything opaque: no sorting and no cost for the merged
## city meshes, which cannot fade one building at a time. The ground and
## anything behind the player stay solid.
class_name Cutaway
extends RefCounted

const RADIUS_M := 7.0
const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 focus = vec3(0.0, -1000.0, 0.0);
uniform vec3 view_dir = vec3(0.0, -1.0, 0.0);
uniform float radius = 7.0;
uniform bool use_vertex = true;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness = 0.95;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 4x4 ordered dither: a hole that looks soft without blending.
float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void fragment() {
	vec3 d = world_pos - focus;
	float along = dot(d, view_dir);
	float off_line = length(d - along * view_dir);
	if (along < -0.8 && world_pos.y > 0.25 && off_line < radius) {
		float hole = smoothstep(radius, radius * 0.55, off_line) * 0.9;
		if (bayer(FRAGCOORD.xy) < hole) {
			discard;
		}
	}
	ALBEDO = use_vertex ? COLOR.rgb : tint;
	ROUGHNESS = roughness;
}
"""

static var _shader: Shader
static var _materials: Array[ShaderMaterial] = []

## A city material that takes part in the cutaway: vertex colours, or one flat colour.
static func material(colour: Color = Color.WHITE, use_vertex: bool = true, roughness: float = 0.95) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("use_vertex", use_vertex)
	mat.set_shader_parameter("tint", colour)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("radius", RADIUS_M)
	_materials.append(mat)
	return mat

## Where the hole points: the player's chest, along the camera's forward line.
static func aim(focus: Vector3, view_dir: Vector3) -> void:
	for mat in _materials:
		mat.set_shader_parameter("focus", focus)
		mat.set_shader_parameter("view_dir", view_dir.normalized())

## A fresh city drops the old materials.
static func reset() -> void:
	_materials.clear()
