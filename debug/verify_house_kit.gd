## K4 validator: houses built from the Blender kit. For the houses round
## the spawn: the kit's front door stands on the sim's own door (where you
## walk in), there is at most one front door per house, every kit part loads,
## the average house's kit stays under AVERAGE triangles and nine in ten
## inside their budget: BASE plus PER_STOREY for each storey.
extends SceneTree

const RADIUS := 120.0
const BASE := 2000         # triangles of kit parts per house (walls and roof are extra)
const PER_STOREY := 2500
const AVERAGE := 4500   # A2b: gutters and downspouts added ~0.9k; the spec allows 2-5k

func _initialize() -> void:
	KitBatch3D.prime()
	var city := CityData.load_file()
	var tri := _part_triangles()
	var houses := 0
	var doors_ok := 0
	var doors_seen := 0
	var over := 0
	var total := 0
	for i in city.buildings.size():
		var b: Dictionary = city.buildings[i]
		if b.get("kind", "") != "house" or b["poly"][0].distance_to(city.spawn) > RADIUS:
			continue
		var m := CityMesh3D.new()
		m.origin = city.spawn
		BuildingMesh3D.add(SurfaceTool.new(), b, m._v, i + 1, m)
		var parts := _parts(m)
		houses += 1
		var span := InteriorSolid.door_span(CityMesh3D._open(b["poly"]), b.get("door", Vector2.INF))
		var doors: Array = parts.get("kit_door_front", [])
		if span.x >= 0:
			doors_seen += 1
			doors_ok += int(doors.size() == 1 and _on_door(doors[0][0].origin, b, span, m.origin))
		var sum := 0
		for part in parts:
			sum += tri.get(part, 0) * (parts[part] as Array).size()
		over += int(sum > BASE + PER_STOREY * maxi(1, int(b.get("levels", 1))))
		total += sum
	var loaded := tri.size() == KitBatch3D.PARTS.size()
	var average := total / maxi(houses, 1)
	var ok := houses > 20 and doors_ok == doors_seen and loaded and over * 10 <= houses and average <= AVERAGE
	print("%d houses; front door on the sim door %d/%d; all parts load %s; kit triangles per house %d on average, %d over their budget" % [houses, doors_ok, doors_seen, loaded, average, over])
	print("HOUSE_KIT_VERIFY: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _parts(m: CityMesh3D) -> Dictionary:
	var all := {}
	for k in m._kits:
		var items: Dictionary = (m._kits[k] as KitBatch3D)._items
		for part in items:
			all.get_or_add(part, []).append_array(items[part])
	return all

func _on_door(at: Vector3, b: Dictionary, span: Vector2, origin: Vector2) -> bool:
	var poly := CityMesh3D._open(b["poly"])
	var a := poly[int(span.x)]
	var c := poly[(int(span.x) + 1) % poly.size()]
	return Vector2(at.x, at.z).distance_to(a.lerp(c, span.y) - origin) < 0.05

func _part_triangles() -> Dictionary:
	var out := {}
	for part in KitBatch3D._meshes:
		var mesh: Mesh = KitBatch3D._meshes[part]
		var n := 0
		for s in mesh.get_surface_count():
			var idx: PackedInt32Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			n += idx.size() / 3 if idx.size() > 0 else mesh.surface_get_array_len(s) / 3
		out[part] = n
	return out
