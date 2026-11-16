## K6 validator, Part C: about one in six one-storey houses is built Spanish:
## an arched front door and arched windows from the kit, no gutters or corner
## boards, and no ordinary front door. Other houses never get the arch parts.
extends SceneTree

const RADIUS := 400.0

func _initialize() -> void:
	KitBatch3D.prime()
	var city := CityData.load_file()
	var spanish := 0
	var spanish_ok := 0
	var plain := 0
	var plain_ok := 0
	for i in city.buildings.size():
		var b: Dictionary = city.buildings[i]
		if b.get("kind", "") != "house" or b["poly"][0].distance_to(city.spawn) > RADIUS:
			continue
		var m := CityMesh3D.new()
		m.origin = b["poly"][0]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		BuildingMesh3D.add(st, b, m._v, i + 1, m)
		var parts := _parts(m)
		var arches: int = parts.get("kit_window_arch", 0) + parts.get("kit_door_arch", 0)
		var is_spanish := int(b.get("levels", 1)) == 1 and absi(String(b["id"]).hash() / 3) % 100 < BuildingMesh3D.SPANISH_SHARE
		if is_spanish:
			spanish += 1
			spanish_ok += int(arches > 0 and not parts.has("kit_gutter") and not parts.has("kit_trim_corner") and not parts.has("kit_door_front"))
		else:
			plain += 1
			plain_ok += int(arches == 0)
	print("%d Spanish houses, %d built right; %d others, %d without arches" % [spanish, spanish_ok, plain, plain_ok])
	var ok := spanish >= 5 and spanish_ok == spanish and plain_ok == plain and spanish * 3 < plain
	print("HOUSE_SPANISH_VERIFY: PASS" if ok else "HOUSE_SPANISH_VERIFY: FAIL - Spanish houses are missing arches or carry the wrong parts")
	quit(0 if ok else 1)

## part -> how many of it this house's kit placed.
func _parts(m: CityMesh3D) -> Dictionary:
	var all := {}
	for k in m._kits:
		var items: Dictionary = (m._kits[k] as KitBatch3D)._items
		for part in items:
			all[part] = all.get(part, 0) + (items[part] as Array).size()
	return all
