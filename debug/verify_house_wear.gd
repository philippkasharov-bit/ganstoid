## K6 validator: a house on a poor block is worn (its stucco marked STUCCO_WORN, so
## the shader stains it) and the poorest get iron bars on their ground-floor
## windows; the same house on a rich block gets neither. Wealth comes from
## BuildingMesh3D.wealth_by_cell, as GameView3D copies it from the economy.
extends SceneTree

func _initialize() -> void:
	var city := CityData.load_file()
	var house: Dictionary = {}
	for b in city.buildings:
		if b.get("kind", "") == "house" and b["poly"][0].distance_to(city.spawn) < 120.0:
			house = b
			break
	var cell := TerritoryData.cell_of(BuildingMesh3D._centroid(house["poly"]))
	var poor := _look(house, cell, 0.2)
	var middling := _look(house, cell, 0.37)
	var rich := _look(house, cell, 0.8)
	BuildingMesh3D.wealth_by_cell = {}
	print("poor: worn %s, bar vertices %d | middling: worn %s, bars %d | rich: worn %s, bars %d" % [poor.x > 0, poor.y, middling.x > 0, middling.y, rich.x > 0, rich.y])
	var ok := poor.x > 0 and poor.y > 0 and middling.x > 0 and middling.y == 0 and rich.x == 0 and rich.y == 0
	print("HOUSE_WEAR_VERIFY: PASS" if ok else "HOUSE_WEAR_VERIFY: FAIL - wear or bars do not follow block wealth")
	quit(0 if ok else 1)

## (vertices marked worn stucco, vertices in bar iron) for the house on a block this wealthy.
func _look(house: Dictionary, cell: Vector2i, wealth: float) -> Vector2i:
	BuildingMesh3D.wealth_by_cell = {cell: wealth}
	var m := CityMesh3D.new()
	m.origin = house["poly"][0]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	BuildingMesh3D.add(st, house, m._v, 1, m)
	var colours: PackedColorArray = st.commit_to_arrays()[Mesh.ARRAY_COLOR]
	var worn := 0
	var bars := 0
	for c in colours:
		worn += int(roundi(c.a * 15.0) == SurfaceDetail.STUCCO_WORN)
		bars += int(Color(c, 1.0).is_equal_approx(Color(HouseKit3D.BAR_IRON, 1.0)))
	return Vector2i(worn, bars)
