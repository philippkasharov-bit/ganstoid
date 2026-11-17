## VS2-0 validator: the baked contact shading (ContactAO3D). Building a piece of
## the city round the spawn gives one shading mesh per chunk, flat just above
## the ground, shaded between the wall-foot darkness and none; its dark edge
## lies on a building outline or a wall/fence foot; and its material is drawn
## see-through after the ground (an opaque one is covered by the ground).
extends SceneTree

const SPAWN := Vector2(5165.2, 3371.5)
const RADIUS := 200.0

func _initialize() -> void:
	var city := CityData.load_file()
	var real := CityReal.load_files()
	var nodes := CityMesh3D.build(city, SPAWN, RADIUS, SPAWN, CityMesh3D.ALL, Rect2(), real)
	var meshes: Array[MeshInstance3D] = []
	for n in nodes:
		if n.name.begins_with("ContactAO"):
			meshes.append(n as MeshInstance3D)
	var fail := ""
	if meshes.is_empty():
		fail = "no contact shading mesh"
	var code: String = (ContactAO3D.material().shader as Shader).code
	if fail == "" and not ("blend_mul" in code and "ALPHA" in code):
		fail = "the material is not multiply-blended and see-through"
	var lo := minf(ContactAO3D.WALL_SHADE, ContactAO3D.LINE_SHADE) - 0.01
	var tris := 0
	var dark: Array[Vector2] = []
	for mi in meshes:
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		tris += verts.size() / 3
		for i in verts.size():
			if fail == "" and absf(verts[i].y - ContactAO3D.LIFT) > 0.001:
				fail = "a shading vertex is not at the lift height (%.3f)" % verts[i].y
			if fail == "" and (cols[i].r < lo or cols[i].r > 1.001):
				fail = "a shade out of range (%.2f)" % cols[i].r
			if cols[i].r < 0.99 and dark.size() < 300 and i % 7 == 0:
				dark.append(Vector2(verts[i].x, verts[i].z) + SPAWN)
	if fail == "" and tris < 200:
		fail = "only %d shading triangles round the spawn" % tris
	if fail == "":
		var off := _off_outline(city, real, dark)
		if off > 0:
			fail = "%d of %d dark edges are not on a building outline or a wall foot" % [off, dark.size()]
	for n in nodes:
		n.free()
	print("CONTACT_AO: %d meshes, %d triangles, %d dark edges checked" % [meshes.size(), tris, dark.size()])
	print("CONTACT_AO_VERIFY: %s" % ("PASS" if fail == "" else "FAIL - " + fail))
	quit(0 if fail == "" else 1)

## How many points are more than 0.4 m from every building edge and barrier line near them.
static func _off_outline(city: CityData, real: CityReal, pts: Array[Vector2]) -> int:
	var lines: Array[PackedVector2Array] = []
	for b in city.buildings:
		var poly: PackedVector2Array = b["poly"]
		if poly[0].distance_to(SPAWN) < RADIUS + 200.0:
			var ring := poly.duplicate()
			ring.append(poly[0])
			lines.append(ring)
	for b in real.barriers:
		if b["pts"][0].distance_to(SPAWN) < RADIUS + 200.0:
			lines.append(b["pts"])
	var off := 0
	for p in pts:
		var best := INF
		for l in lines:
			for i in l.size() - 1:
				best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, l[i], l[i + 1])))
		if best > 0.4:
			off += 1
	return off
