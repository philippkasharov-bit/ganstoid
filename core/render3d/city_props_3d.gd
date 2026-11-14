## D2: what stands up out of the streets besides palms: shade trees (every
## surveyed tree, plus one in the yard of many houses, never inside a
## house), and LA's overhead power lines on wooden poles down residential
## streets, three wires from pole to pole. MultiMeshes with the Cutaway
## material, so they are cut away like palms when they stand in front of you.
class_name CityProps3D
extends RefCounted

const POLE_EVERY := 42.0
const POLE_H := 9.0
const WIRE_H := 8.4
const YARD_TREE_SHARE := 0.45
const TRUNK := Color("6e5843")
const LEAVES := [Color("4f7a3a"), Color("5c8840")]
const WOOD := Color("6b5a47")
const WIRE := Color("2b2b2e")
const CAN := Color("8e9396")
const TRANSFORMER_H := 6.9

## Trees and power lines within `radius` of `centre`, in the 3D view's space.
## OPT1: placed relative to `origin`; with `keep`, only what stands inside it (its chunk).
static func build(city: CityData, real: CityReal, centre: Vector2, radius: float, origin: Vector2 = Vector2.INF, keep: Rect2 = Rect2()) -> Array[Node3D]:
	if origin == Vector2.INF:
		origin = centre
	var spots := PackedVector2Array()
	for t in real.trees:
		if t.distance_to(centre) < radius:
			spots.append(t)
	spots.append_array(_yard_trees(city, real, centre, radius))
	var kept := PackedVector2Array()
	for t in spots:
		if not keep.has_area() or keep.has_point(t):
			kept.append(t)
	var out: Array[Node3D] = []
	out.append_array(_trees(kept, origin))
	out.append_array(_power(city, centre, radius, origin, keep))
	return out

## One tree in the yard of many houses: a lot corner pulled in, clear of every house.
static func _yard_trees(city: CityData, real: CityReal, centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var homes := Footprints.build(city, centre, radius + 20.0)
	for lot in real.lots:
		var poly: PackedVector2Array = lot["poly"]
		if lot["use"] != "house" or poly[0].distance_to(centre) > radius:
			continue
		var roll := absi(int(poly[0].x * 31.0 + poly[0].y * 17.0)) % 100
		if roll >= int(YARD_TREE_SHARE * 100.0):
			continue
		var mid := Vector2.ZERO
		for p in poly:
			mid += p / poly.size()
		var spot := poly[roll % poly.size()].lerp(mid, 0.22)
		if homes.at(spot).is_empty() and homes.at(spot + Vector2(2, 2)).is_empty() and homes.at(spot - Vector2(2, 2)).is_empty():
			out.append(spot)
	return out

static func _trees(spots: PackedVector2Array, centre: Vector2) -> Array[Node3D]:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.22
	trunk.height = 3.2
	trunk.radial_segments = 6
	var crown := SphereMesh.new()
	crown.radius = 2.4
	crown.height = 3.6
	crown.radial_segments = 8
	crown.rings = 4
	var trunks := _multi(trunk, Cutaway.shared("tree_trunk", TRUNK, false, 1.0), spots.size())
	var crowns := _multi(crown, Cutaway.shared("tree_crown", LEAVES[1], false, 1.0, 0.0, 0.6), spots.size())
	for i in spots.size():
		var p := Vector3(spots[i].x - centre.x, 0, spots[i].y - centre.y)
		var size := 0.75 + float(absi(int(spots[i].x * 11.0)) % 50) / 100.0
		var turn := Basis(Vector3.UP, spots[i].y).scaled(Vector3.ONE * size)
		trunks.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, size, 1)), p + Vector3(0, 1.6 * size, 0)))
		crowns.multimesh.set_instance_transform(i, Transform3D(turn, p + Vector3(0, 4.2 * size, 0)))
	return [trunks, crowns]

## Wooden poles down one side of residential streets, three wires pole to pole.
static func _power(city: CityData, centre: Vector2, radius: float, origin: Vector2, keep: Rect2) -> Array[Node3D]:
	var poles: Array = []   # [point, along-road direction]
	var wires: Array = []   # [a, b]
	for r in city.roads:
		var pts: PackedVector2Array = r["pts"]
		if r["tier"] != "res" or pts[0].distance_to(centre) > radius:
			continue
		var off: float = float(r.get("w", 6.0)) * 0.5 + 1.1
		var run := POLE_EVERY * 0.5
		var last := Vector2.INF
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			var length := seg.length()
			while run < length and length > 0.0:
				var at := pts[i] + seg * (run / length) + seg.normalized().orthogonal() * off
				if not keep.has_area() or keep.has_point(at):
					poles.append([at, seg.normalized()])
					if last != Vector2.INF and last.distance_to(at) < POLE_EVERY * 1.6:
						wires.append([last, at])
				last = at
				run += POLE_EVERY
			run -= length
	return _poles_and_wires(poles, wires, origin)

static func _poles_and_wires(poles: Array, wires: Array, centre: Vector2) -> Array[Node3D]:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.11
	pole.bottom_radius = 0.15
	pole.height = POLE_H
	pole.radial_segments = 6
	var bar := BoxMesh.new()
	bar.size = Vector3(1.0, 1.0, 1.0)
	var posts := _multi(pole, Cutaway.shared("pole", WOOD, false, 1.0), poles.size())
	var arms := _multi(bar, Cutaway.shared("pole", WOOD, false, 1.0), poles.size())
	var lines := _multi(bar, Cutaway.shared("wire", WIRE, false, 1.0), wires.size() * 3)
	for i in poles.size():
		var p: Vector2 = poles[i][0]
		var across: Vector2 = (poles[i][1] as Vector2).orthogonal()
		var at := Vector3(p.x - centre.x, 0, p.y - centre.y)
		posts.multimesh.set_instance_transform(i, Transform3D(Basis(), at + Vector3(0, POLE_H * 0.5, 0)))
		arms.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -across.angle()).scaled_local(Vector3(1.9, 0.12, 0.12)), at + Vector3(0, WIRE_H + 0.1, 0)))
	for i in wires.size():
		var a: Vector2 = wires[i][0]
		var b: Vector2 = wires[i][1]
		var dir := (b - a).normalized()
		var mid := (a + b) * 0.5
		for k in 3:
			var side := dir.orthogonal() * (k - 1) * 0.8
			var at := Vector3(mid.x + side.x - centre.x, WIRE_H + 0.2, mid.y + side.y - centre.y)
			lines.multimesh.set_instance_transform(i * 3 + k, Transform3D(Basis(Vector3.UP, -dir.angle()).scaled_local(Vector3(a.distance_to(b), 0.035, 0.035)), at))
	return [posts, arms, lines, _transformers(poles, centre)]

## G4: a grey transformer can hung on every fourth pole.
static func _transformers(poles: Array, centre: Vector2) -> MultiMeshInstance3D:
	var can := CylinderMesh.new()
	can.top_radius = 0.27
	can.bottom_radius = 0.27
	can.height = 0.95
	can.radial_segments = 8
	var cans := _multi(can, Cutaway.shared("transformer", CAN, false, 0.7), (poles.size() + 1) / 4)
	for k in cans.multimesh.instance_count:
		var p: Vector2 = poles[k * 4][0]
		var off: Vector2 = (poles[k * 4][1] as Vector2) * 0.38
		cans.multimesh.set_instance_transform(k, Transform3D(Basis(), Vector3(p.x + off.x - centre.x, TRANSFORMER_H, p.y + off.y - centre.y)))
	return cans

static func _multi(mesh: Mesh, mat: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
