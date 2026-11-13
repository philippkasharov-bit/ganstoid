## R3D4/R3D7: you never lose sight of yourself. Sims-style wall cut mixed
## with Zomboid's "what stands in front of you goes": every building between
## the camera and the player is cut, whole and cleanly, down to a low wall
## with a dark cap line along the cut (no fading, no dither). Palms in front
## lose their crown and trunk the same way. Footprints.covering picks the
## buildings that hide you; each building's vertices carry its tag (UV.y),
## so the merged city meshes still cut one building at a time.
## R3D8: Zomboid's vision cone: what is outside your field of view (and,
## indoors, everything outside the room) is drawn dark and grey; a small
## ring round you is always seen.
## R3D10: night: the city goes dark except in lamp pools and headlights
## (DayNight3D sends them), and lit windows and shop fronts glow.
## R3D11: walls block sight (SightMap): past the nearest wall it is dark.
## R3D5: inside a building, its roof and upper floors go, and the walls on
## the camera's side drop to waist height, so you see the room you are in.
class_name Cutaway
extends RefCounted

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 focus = vec3(0.0, -1000.0, 0.0);
uniform vec3 view_dir = vec3(0.0, -1.0, 0.0);
uniform int cut_tags[16];         // the buildings hiding you (Footprints.covering)
uniform int cut_count = 0;
uniform float clear_m = 2.5;      // palms this near your sight line lose their crown
uniform float cut_h = 1.1;        // the low wall left standing
uniform float cap_m = 0.14;       // the dark line along the cut
uniform bool use_vertex = true;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness = 0.95;
uniform bool room_on = false;
uniform vec2 room_min = vec2(0.0);
uniform vec2 room_max = vec2(0.0);
uniform float ceiling = 2.6;
uniform float waist = 1.0;
uniform vec2 look = vec2(1.0, 0.0);   // where you face, 3D x/z
uniform float cone_cos = 0.34;        // half the field of view (about 70 degrees)
uniform float near_m = 3.5;           // always seen round you
uniform float unseen = 0.42;          // how bright the unseen world is
uniform float night = 0.0;            // 0 day .. 1 night
uniform vec4 lights[96];              // x, z (3D), radius, strength
uniform int light_count = 0;
uniform float moon = 0.28;
uniform float sight[360];             // R3D11: how far you can see each degree round you (SightMap)
uniform bool sight_on = false;
uniform float self_glow = 0.0;        // lamp heads: lit at night
varying float glow;                   // a lit window / shop front (UV.x)
varying vec3 world_pos;
varying flat int tag;  // the building this vertex belongs to (0: road, ground, palm)
varying vec2 palm;     // a palm's foot in 3D x/z

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tag = use_vertex ? int(UV.y + 0.5) : 0;   // flat meshes (ground, palms) have their own UVs
	glow = use_vertex ? UV.x : 0.0;
	palm = vec2(MODEL_MATRIX[3].x, MODEL_MATRIX[3].z);
}

// Is this whole building (or palm) between the camera and you?
bool in_front() {
	if (use_vertex) {
		for (int i = 0; i < cut_count; i++) {
			if (cut_tags[i] == tag) {
				return true;
			}
		}
		return false;
	}
	vec2 v = normalize(view_dir.xz);
	vec2 d = palm - focus.xz;
	return dot(d, v) < 0.0 && dot(d, v) > -30.0 && abs(d.x * v.y - d.y * v.x) < clear_m + 1.2;
}

bool cut_room() {
	vec2 p = world_pos.xz;
	if (!room_on || any(lessThan(p, room_min)) || any(greaterThan(p, room_max))) {
		return false;
	}
	vec2 toward_camera = -normalize(view_dir.xz);
	bool near_side = dot(p - (room_min + room_max) * 0.5, toward_camera) > 0.0;
	return world_pos.y > ceiling || (near_side && world_pos.y > waist);
}

// Lamp pools and headlights here (0..1).
float lamp() {
	float sum = 0.0;
	for (int i = 0; i < light_count; i++) {
		float d = distance(world_pos.xz, lights[i].xy);
		sum += (1.0 - smoothstep(lights[i].z * 0.3, lights[i].z, d)) * lights[i].w;   // = StreetLights.pool
	}
	return min(sum, 1.0);
}

// 1: in your field of view; 0: not seen (soft edges).
float seen() {
	vec2 d = world_pos.xz - focus.xz;
	float dist = length(d);
	float ring = 1.0 - smoothstep(near_m, near_m + 1.5, dist);
	float cone = smoothstep(cone_cos - 0.12, cone_cos + 0.06, dot(d / max(dist, 0.001), normalize(look)));
	float v = max(ring, cone);
	if (sight_on && tag == 0) {   // walls hide what is behind them (building shells keep their outside)
		float a = atan(d.y, d.x);
		int bin = int(mod(floor(a / 6.2831853 * 360.0), 360.0));
		v *= 1.0 - smoothstep(sight[bin] + 0.2, sight[bin] + 0.9, dist);
	}
	if (room_on) {
		vec2 p = world_pos.xz;
		bool inside = all(greaterThanEqual(p, room_min)) && all(lessThanEqual(p, room_max));
		v = inside ? v : v * 0.15;   // indoors: outside is a dark blur, as through walls
	}
	return focus.y < -100.0 ? 1.0 : v;
}

void fragment() {
	bool cut = in_front();
	if (cut_room() || (cut && world_pos.y > cut_h)) {
		discard;
	}
	vec3 col = use_vertex ? COLOR.rgb : tint;
	if (cut && world_pos.y > cut_h - cap_m) {
		col *= 0.45;   // the cap: the cut reads as a wall top, not a hole
	}
	float lit = seen();
	vec3 grey = vec3(dot(col, vec3(0.3, 0.59, 0.11)));
	float pool = lamp();
	float bright = mix(1.0, max(moon, pool), night);   // at night you see what is lit
	float dim = mix(0.68, unseen, night);   // by day the unseen world is only a little dimmer (Zomboid)
	ALBEDO = mix(mix(grey, col, mix(0.6, 0.35, night)) * dim, col, lit) * bright;
	EMISSION = night * (vec3(1.0, 0.8, 0.5) * pool * 0.6 * col + vec3(1.0, 0.82, 0.5) * glow * 0.9 + tint * self_glow);
	ROUGHNESS = roughness;
}
"""

static var _shader: Shader
static var _materials: Array[ShaderMaterial] = []

## A city material that takes part in the cutaway: vertex colours, or one flat colour.
static func material(colour: Color = Color.WHITE, use_vertex: bool = true, roughness: float = 0.95, glows: float = 0.0) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("use_vertex", use_vertex)
	mat.set_shader_parameter("tint", colour)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("self_glow", glows)
	_materials.append(mat)
	return mat

## Where you are and which way the camera looks: what is in front gets cut.
static func aim(focus: Vector3, view_dir: Vector3) -> void:
	for mat in _materials:
		mat.set_shader_parameter("focus", focus)
		mat.set_shader_parameter("view_dir", view_dir.normalized())

## R3D10: how dark it is and the lights near you (x, z in 3D, radius, strength).
static func light(dark: float, lights: PackedVector4Array) -> void:
	var list := lights.duplicate()
	list.resize(96)
	for mat in _materials:
		mat.set_shader_parameter("night", dark)
		mat.set_shader_parameter("lights", list)
		mat.set_shader_parameter("light_count", mini(lights.size(), 96))

## R3D11: the sight depth round you (SightMap.depth), or none.
static func sight(depth: PackedFloat32Array) -> void:
	for mat in _materials:
		mat.set_shader_parameter("sight_on", not depth.is_empty())
		if not depth.is_empty():
			mat.set_shader_parameter("sight", depth)

## R3D8: which way you face (map radians): the vision cone.
static func facing(angle: float) -> void:
	for mat in _materials:
		mat.set_shader_parameter("look", Vector2.from_angle(angle))

## R3D7: the buildings to cut (tags from Footprints.covering).
static func cut(tags: PackedInt32Array) -> void:
	var list := tags.duplicate()
	list.resize(16)
	for mat in _materials:
		mat.set_shader_parameter("cut_tags", list)
		mat.set_shader_parameter("cut_count", mini(tags.size(), 16))

## R3D5: the room you are in (its footprint's box in 3D x/z), or none.
static func room(box: Rect2, on: bool) -> void:
	for mat in _materials:
		mat.set_shader_parameter("room_on", on)
		mat.set_shader_parameter("room_min", box.position - Vector2.ONE * 0.4)
		mat.set_shader_parameter("room_max", box.end + Vector2.ONE * 0.4)

## A fresh city drops the old materials.
static func reset() -> void:
	_materials.clear()
