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
## TX1: surfaces marked with a material (SurfaceDetail) get a world-mapped
## detail texture over their colour: top-down on ground and roofs, along the
## wall on walls.
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
uniform float sway = 0.0;             // D2: palms and trees in the breeze
uniform sampler2DArray detail : filter_linear_mipmap, repeat_enable;   // TX1: SurfaceDetail maps
uniform float tile_m[15];
uniform float strength[15];
uniform bool decal_on = false;       // B2: a graffiti mesh: colour and cut-out from the atlas (UV2)
uniform sampler2D decal_tex : source_color, filter_linear_mipmap;
uniform bool kit_on = false;          // K4: house-kit parts (MultiMesh): the baked sheet, painted by its alpha mask
uniform sampler2D kit_atlas : source_color, filter_linear_mipmap, repeat_disable;
const vec3 DOOR_PAINT[8] = vec3[8](vec3(0.184, 0.29, 0.227), vec3(0.541, 0.165, 0.141), vec3(0.122, 0.176, 0.29), vec3(0.11, 0.11, 0.118),
	vec3(0.42, 0.29, 0.18), vec3(0.937, 0.918, 0.878), vec3(0.165, 0.42, 0.42), vec3(0.722, 0.537, 0.18));   // = KitBatch3D.DOOR_PAINT (a uniform array here upset the others in the compatibility renderer)
varying flat float kit_door;
uniform int plain_surface = 15;       // TX3: a one-colour mesh's material (the ground)
varying vec3 wnormal;
varying float glow;                   // a lit window / shop front (UV.x)
varying vec3 world_pos;
varying flat int tag;  // the building this vertex belongs to (0: road, ground, palm)
varying vec2 palm;     // a palm's foot in 3D x/z

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (sway > 0.0) {   // D2: tree tops move in the breeze, more the higher they are
		float h = max(world_pos.y - 3.0, 0.0);
		vec3 wind = vec3(sin(TIME * 1.1 + world_pos.x * 0.13), 0.0, cos(TIME * 0.9 + world_pos.z * 0.11)) * sway * h * 0.035;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(wind, 0.0)).xyz;
		world_pos += wind;
	}
	tag = use_vertex ? int(UV.y + 0.5) : 0;   // flat meshes (ground, palms) have their own UVs
	glow = use_vertex ? UV.x : 0.0;
	if (kit_on) {   // K4: a kit copy carries its house's tag, lit window and door colour
		tag = int(INSTANCE_CUSTOM.r * 255.0 + 0.5) + 256 * int(INSTANCE_CUSTOM.a * 255.0 + 0.5);   // KitBatch3D.custom: survives 8-bit storage
		glow = INSTANCE_CUSTOM.g;
		kit_door = INSTANCE_CUSTOM.b * 7.0;
	}
	palm = vec2(MODEL_MATRIX[3].x, MODEL_MATRIX[3].z);
}

// Is this whole building (or palm) between the camera and you?
bool in_front(vec3 wp) {
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

bool cut_room(vec3 wp) {
	vec2 p = wp.xz;
	if (!room_on || any(lessThan(p, room_min)) || any(greaterThan(p, room_max))) {
		return false;
	}
	vec2 toward_camera = -normalize(view_dir.xz);
	bool near_side = dot(p - (room_min + room_max) * 0.5, toward_camera) > 0.0;
	return wp.y > ceiling || (near_side && wp.y > waist);
}

// TX1: the material's grain here, 1.0 = no change (top-down on flats, along the wall on walls).
float grain(int id, vec3 wp) {
	vec2 uv = wp.xz;
	if (abs(wnormal.y) < 0.5) {
		vec2 along = normalize(vec2(-wnormal.z, wnormal.x) + vec2(0.0001));
		uv = vec2(dot(wp.xz, along), -wp.y);
	}
	float d = texture(detail, vec3(uv / tile_m[id], float(id))).r;
	if (id == 5 || id == 6 || id == 8 || id == 9) {   // gravel, asphalt, grass, dirt: a second, turned and larger copy breaks the repeat
		vec2 turned = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv;
		d = 0.5 + (d + texture(detail, vec3(turned / (tile_m[id] * 2.37), float(id))).r - 1.0) * 0.75;
	}
	return 1.0 + (d - 0.5) * 2.0 * strength[id];
}

// Lamp pools and headlights here (0..1).
float lamp(vec3 wp) {
	float sum = 0.0;
	for (int i = 0; i < light_count; i++) {
		float d = distance(wp.xz, lights[i].xy);
		sum += (1.0 - smoothstep(lights[i].z * 0.3, lights[i].z, d)) * lights[i].w;   // = StreetLights.pool
	}
	return min(sum, 1.0);
}

// 1: in your field of view; 0: not seen (soft edges).
float seen(vec3 wp) {
	vec2 d = wp.xz - focus.xz;
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
		vec2 p = wp.xz;
		bool inside = all(greaterThanEqual(p, room_min)) && all(lessThanEqual(p, room_max));
		v = inside ? v : v * 0.15;   // indoors: outside is a dark blur, as through walls
	}
	return focus.y < -100.0 ? 1.0 : v;
}

void fragment() {
	// K4: the world point from the camera: right for MultiMesh copies too (in the
	// compatibility renderer MODEL_MATRIX leaves out each copy's own transform)
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bool cut = in_front(wp);
	if (cut_room(wp) || (cut && wp.y > cut_h)) {
		discard;
	}
	vec3 col = use_vertex ? COLOR.rgb : tint * COLOR.rgb;   // G3: a MultiMesh may tint each instance
	if (decal_on) {
		vec4 paint = texture(decal_tex, UV2);
		if (paint.a < 0.45) {
			discard;
		}
		col = paint.rgb * COLOR.rgb;   // vertex colour fades old tags
	}
	float lit_glass = glow;
	if (kit_on) {
		vec4 sheet = texture(kit_atlas, UV);
		int cell = int(floor(UV.y * 4.0)) * 4 + int(floor(UV.x * 4.0));   // kit_lib.SLOTS order
		vec3 paint = cell == 1 ? DOOR_PAINT[clamp(int(kit_door + 0.5), 0, 7)] : COLOR.rgb;
		col = mix(sheet.rgb, sheet.rgb * paint, sheet.a);
		lit_glass = (cell == 2 || cell == 3) ? glow : 0.0;
	}
	int surface = (use_vertex && !kit_on) ? int(COLOR.a * 15.0 + 0.5) : plain_surface;
	if (surface < 15) {
		col *= grain(surface, wp);
	}
	if (cut && wp.y > cut_h - cap_m) {
		col *= 0.45;   // the cap: the cut reads as a wall top, not a hole
	}
	float lit = seen(wp);
	vec3 grey = vec3(dot(col, vec3(0.3, 0.59, 0.11)));
	float pool = lamp(wp);
	float bright = mix(1.0, max(moon, pool), night);   // at night you see what is lit
	float dim = mix(0.68, unseen, night);   // by day the unseen world is only a little dimmer (Zomboid)
	vec3 sodium = mix(vec3(1.0), vec3(1.0, 0.78, 0.5), clamp(pool, 0.0, 1.0) * night);   // P1: lamp light is warm sodium, not grey fog
	ALBEDO = mix(mix(grey, col, mix(0.6, 0.35, night)) * dim, col, lit) * bright * sodium;
	EMISSION = night * (vec3(1.0, 0.72, 0.4) * pool * 0.55 * col + vec3(1.0, 0.82, 0.5) * lit_glass * 0.9 + tint * self_glow);
	ROUGHNESS = roughness;
}
"""

static var _shader: Shader
static var _materials: Array[ShaderMaterial] = []

## A city material that takes part in the cutaway: vertex colours, or one flat colour.
static func material(colour: Color = Color.WHITE, use_vertex: bool = true, roughness: float = 0.95, glows: float = 0.0, breeze: float = 0.0) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("use_vertex", use_vertex)
	mat.set_shader_parameter("tint", colour)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("self_glow", glows)
	mat.set_shader_parameter("sway", breeze)
	if use_vertex:   # TX1: only vertex-coloured meshes carry a material
		made_of(mat, SurfaceDetail.NONE)
	_materials.append(mat)
	return mat

## TX1/TX3: give `mat` the detail maps; a one-colour material is all `surface`.
static func made_of(mat: ShaderMaterial, surface: int) -> ShaderMaterial:
	mat.set_shader_parameter("detail", SurfaceDetail.textures())
	var tiles := PackedFloat32Array(SurfaceDetail.TILE_M)
	var strengths := PackedFloat32Array(SurfaceDetail.STRENGTH)
	tiles.resize(SurfaceDetail.SLOTS)
	strengths.resize(SurfaceDetail.SLOTS)
	mat.set_shader_parameter("tile_m", tiles)
	mat.set_shader_parameter("strength", strengths)
	mat.set_shader_parameter("plain_surface", surface)
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
	_shared.clear()

static var _shared: Dictionary = {}

## OPT1: one material per look, shared by every streamed chunk (a new one per
## chunk would pile up and each would be updated every frame).
static func shared(key: String, colour: Color = Color.WHITE, use_vertex: bool = true, roughness: float = 0.95, glows: float = 0.0, breeze: float = 0.0) -> ShaderMaterial:
	if not _shared.has(key):
		_shared[key] = material(colour, use_vertex, roughness, glows, breeze)
	return _shared[key]
