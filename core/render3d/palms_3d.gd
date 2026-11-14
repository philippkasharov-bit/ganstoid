## G3: LA's palms. Each street-well palm is a ringed trunk (some much taller
## than others, all leaning a little), a skirt of dead brown fronds under
## the crown, and a crown of fourteen long fronds that arch up and droop at
## the tip, each palm its own green. Three MultiMeshes per chunk; the
## crown sways (Cutaway sway) and palms in front of you lose their crown.
class_name Palms3D
extends RefCounted

const TRUNK_H := 9.0
const FRONDS := 14
const GREENS := [Color("4f7a3a"), Color("5a8441"), Color("486f35"), Color("62894a")]
const TRUNK := Color("7a5f45")
const SKIRT := Color("8a7350")
const LEAN_DEG := 4.0

## The palms at `wells` (map points); `v` turns a map point and height into 3D.
static func build(wells: PackedVector2Array, v: Callable) -> Array[Node3D]:
	var trunks := _layer(_trunk(), Cutaway.shared("palm_trunk", TRUNK, false, 1.0), wells.size())
	var skirts := _layer(_skirt(), Cutaway.shared("palm_skirt", SKIRT, false, 1.0, 0.0, 0.5), wells.size())
	var crowns := _layer(crown(), Cutaway.shared("palm_crown", Color.WHITE, false, 1.0, 0.0, 1.0), wells.size())
	for i in wells.size():
		var roll := absi(hash(wells[i]))
		var tall := 0.8 + float(roll % 60) / 100.0   # a Mexican fan palm beside a shorter date palm
		var lean := Basis(Vector3(cos(roll), 0, sin(roll)).normalized(), deg_to_rad(float(roll % 100) / 100.0 * LEAN_DEG))
		var foot: Vector3 = v.call(wells[i], 0.0)
		var top := foot + lean * Vector3(0, TRUNK_H * tall, 0)
		var turn := lean * Basis(Vector3.UP, float(roll % 360) * PI / 180.0)
		trunks.multimesh.set_instance_transform(i, Transform3D(lean.scaled_local(Vector3(1, tall, 1)), foot + lean * Vector3(0, TRUNK_H * tall * 0.5, 0)))
		skirts.multimesh.set_instance_transform(i, Transform3D(turn, top - Vector3(0, 0.75, 0)))
		crowns.multimesh.set_instance_transform(i, Transform3D(turn, top))
		crowns.multimesh.set_instance_color(i, GREENS[roll % GREENS.size()])
	var blobs := BlobShadows3D.layer(wells.size())   # A2a: the crown's patch of shade, under the top (palms lean)
	for i in wells.size():
		var top := crowns.multimesh.get_instance_transform(i).origin
		BlobShadows3D.place(blobs, i, top, Vector2.ONE * 4.2, 0.0, 0.4)
	return [trunks, skirts, crowns, blobs]

static func _trunk() -> Mesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.28
	trunk.height = TRUNK_H
	trunk.radial_segments = 8
	trunk.rings = 1
	return trunk

## The dead fronds hanging under the crown: a short ragged cone.
static func _skirt() -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.6
	cone.bottom_radius = 0.3
	cone.height = 1.5
	cone.radial_segments = 9
	cone.rings = 1
	return cone

static var _crown_mesh: ArrayMesh

## The crown, made once (GameView3D.setup primes it on the main thread).
static func crown() -> ArrayMesh:
	if _crown_mesh == null:
		_crown_mesh = _crown()
	return _crown_mesh

## FRONDS long leaves round the top, each in three pieces: up, out, drooping down.
static func _crown() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in FRONDS:
		var d := Vector2.from_angle(k * TAU / FRONDS + float(k % 3) * 0.12)
		var reach := 2.6 + float(k % 4) * 0.35
		var lift := 0.3 if k % 2 == 0 else -0.1
		var spine := [Vector3(0, 0.1, 0), Vector3(d.x * reach * 0.35, 0.7 + lift, d.y * reach * 0.35),
			Vector3(d.x * reach * 0.7, 0.45 + lift, d.y * reach * 0.7), Vector3(d.x * reach, -0.5 + lift, d.y * reach)]
		var widths := [0.05, 0.42, 0.32, 0.04]
		var side := Vector3(-d.y, 0, d.x)
		for s in 3:
			var a: Vector3 = spine[s]
			var b: Vector3 = spine[s + 1]
			var wa: Vector3 = side * float(widths[s])
			var wb: Vector3 = side * float(widths[s + 1])
			st.set_normal((b - a).cross(side).normalized() * -1.0)
			for p in [a - wa, b - wb, b + wb, a - wa, b + wb, a + wa]:
				st.add_vertex(p)
	return st.commit()

static func _layer(mesh: Mesh, mat: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = mesh is ArrayMesh
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
