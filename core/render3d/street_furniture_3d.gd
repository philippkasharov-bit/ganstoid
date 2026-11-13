## R3D13: what stands at junctions and kerbs near you, in 3D (StreetFurniture's
## twin): traffic signals on poles with their live colour and white stop
## lines, stop signs (red octagon on a post) with their lines, and bus stop
## shelters. MultiMeshes, refreshed a few times a second round the player.
class_name StreetFurniture3D
extends Node3D

const RANGE_M := 160.0
const REFRESH_S := 0.25
const MAX := 400
const POLE := Color("2b2b2e")
const LIGHTS := {"green": Color("3fd16b"), "yellow": Color("f2c230"), "red": Color("ea3b3b")}

var world: World
var origin := Vector2.ZERO
var _left := 0.0
var _poles := _layer(_cyl(0.07, 4.2, 6), false)
var _heads := _layer(_box(Vector3(0.35, 0.9, 0.3)), true)     # signal heads, lit in their colour
var _signs := _layer(_cyl(0.42, 0.04, 8), false)               # stop sign plates
var _lines := _layer(_box(Vector3(1.0, 0.02, 0.35)), false)    # stop lines, stretched to the lane
var _shelters := _layer(_box(Vector3(3.6, 0.12, 1.3)), false)

func _ready() -> void:
	for l in [_poles, _heads, _signs, _lines, _shelters]:
		add_child(l)

func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or world == null or TrafficSystem.junctions == null:
		return
	_left = REFRESH_S
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null:
		_rebuild((player.get_component(ComponentNames.NPC) as NPCData).position)

func _rebuild(at: Vector2) -> void:
	var j := TrafficSystem.junctions
	var secs := float(world.tick) / SimClock.TICKS_PER_SECOND
	var n := {"pole": 0, "head": 0, "sign": 0, "line": 0, "shelter": 0}
	for x in j.near(at, RANGE_M):
		for leg in x["legs"]:
			var into: Vector2 = leg[0]
			var w: float = leg[1]
			var right := Vector2(-into.y, into.x)
			var stop_at: Vector2 = x["c"] - into * (w * 0.5 + 3.0)
			var kerb := stop_at + right * (w * 0.5 + 0.6)
			_put(_lines, n, "line", stop_at + right * w * 0.25, into.angle(), Vector3(0.35, 1, w * 0.5), 0.02, Color(1, 1, 1, 1))
			_put(_poles, n, "pole", kerb, 0.0, Vector3.ONE, 2.1, POLE)
			if x["kind"] == "signal":
				_put(_heads, n, "head", kerb, into.angle(), Vector3.ONE, 4.0, LIGHTS[Junctions.light(x, into, secs)])
			else:
				_put(_signs, n, "sign", kerb - into * 0.1, 0.0, Vector3.ONE, 2.3, Color("c62828"), Basis(Vector3.UP, -into.angle()) * Basis(Vector3.FORWARD, PI * 0.5))
	for b in j.bus_stops:
		if b["c"].distance_to(at) <= RANGE_M:
			var d: Vector2 = b["dir"]
			_put(_shelters, n, "shelter", b["c"] + Vector2(-d.y, d.x) * 1.2, d.angle(), Vector3.ONE, 2.4, Color("2a5d9f"))
	for pair in [[_poles, "pole"], [_heads, "head"], [_signs, "sign"], [_lines, "line"], [_shelters, "shelter"]]:
		pair[0].multimesh.visible_instance_count = n[pair[1]]

## One instance at map point `p`, turned to `angle`, scaled, raised to `h`.
func _put(layer: MultiMeshInstance3D, n: Dictionary, key: String, p: Vector2, angle: float, scale: Vector3, h: float, col: Color, basis := Basis()) -> void:
	var i: int = n[key]
	if i >= MAX:
		return
	var b := basis if basis != Basis() else Basis(Vector3.UP, -angle)
	layer.multimesh.set_instance_transform(i, Transform3D(b.scaled_local(scale), Vector3(p.x - origin.x, h, p.y - origin.y)))
	layer.multimesh.set_instance_color(i, col)
	n[key] = i + 1

static func _layer(mesh: Mesh, lit: bool) -> MultiMeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	if lit:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # a signal shines day and night
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _cyl(r: float, h: float, sides: int) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	return _as_array(c)

static func _box(size: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	return _as_array(b)

static func _as_array(m: PrimitiveMesh) -> ArrayMesh:
	var a := ArrayMesh.new()
	a.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.get_mesh_arrays())
	return a
