## PF3: where the triangles go. Groups every drawn mesh under `root` by its
## material (one material is one layer: city chunks, kit parts, palms, props,
## lamps, blobs ...), sums triangles x copies, and prints the biggest groups
## with a sample mesh size so each can be told apart.
class_name RenderBreakdown
extends RefCounted

static func report(root: Node, top: int = 14) -> void:
	var groups := {}   # material id -> [tris, nodes, shadow tris, label]
	_walk(root, groups)
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][0] > groups[b][0])
	var total := 0
	for k in keys:
		total += groups[k][0]
	print("PF3: %d triangles in %d groups" % [total, keys.size()])
	for k in keys.slice(0, top):
		var g: Array = groups[k]
		print("  %8d tris  %4d nodes  shadow %8d  %s" % [g[0], g[1], g[2], g[3]])

static func _walk(n: Node, groups: Dictionary) -> void:
	if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
		var info := _tris(n)
		if info[0] > 0:
			var mat: Material = (n as GeometryInstance3D).material_override
			var key: int = (mat.get_instance_id() if mat != null else 0) ^ (_mesh_of(n).get_instance_id() if OS.has_environment("PF3_BY_MESH") and _mesh_of(n) != null else 0)
			if not groups.has(key):
				groups[key] = [0, 0, 0, info[1]]
			groups[key][0] += info[0]
			groups[key][1] += 1
			if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				groups[key][2] += info[0]
	for c in n.get_children():
		_walk(c, groups)

## [triangles drawn, label] for one node.
static func _tris(n: Node) -> Array:
	var mesh: Mesh = null
	var copies := 1
	if n is MultiMeshInstance3D and n.multimesh != null:
		mesh = n.multimesh.mesh
		copies = n.multimesh.visible_instance_count if n.multimesh.visible_instance_count >= 0 else n.multimesh.instance_count
	elif n is MeshInstance3D:
		mesh = n.mesh
	if mesh == null:
		return [0, ""]
	var tris := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var size := mesh.get_aabb().size
	return [tris * copies, "%s %s mesh %.1fx%.1fx%.1f m, %d tris each" % [n.get_class(), n.name.substr(0, 18), size.x, size.y, size.z, tris]]

static func _mesh_of(n: Node) -> Mesh:
	if n is MultiMeshInstance3D:
		return n.multimesh.mesh if n.multimesh != null else null
	return n.mesh if n is MeshInstance3D else null
