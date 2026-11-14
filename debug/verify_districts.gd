## T3 validator: blocks are capture points, districts roll them up.
##   1. Two points on opposite sides of a street are different capture points.
##   2. Taking over half a district's blocks makes the district yours; less does not.
##   3. A T2 save (street keys) migrates onto its blocks.
extends SceneTree

func _initialize() -> void:
	var h := Hoods.data()
	if not _check(h != null and h.blocks.size() > 100, "the block map is there"):
		return
	var a := h.blocks[0]
	var across: Vector2i = Vector2i(a["next"][0], Hoods.BLOCK_Y)
	var ka := TerritoryData.turf_of(a["c"])
	var kb := TerritoryData.turf_of(h.block(across)["c"])
	if not _check(Hoods.is_block(ka) and ka != kb, "neighbouring blocks are separate capture points (%s vs %s)" % [ka, kb]):
		return
	var t := TerritoryData.new()
	var district := h.district_of(ka)
	var all := DistrictControl.blocks_in(district)
	print("district %s: %d blocks, %d districts" % [district, all.size(), DistrictControl.names().size()])
	var half := all.size() / 2
	for i in half:
		TerritorySystem.set_influence(t, all[i], &"player", 90.0)
	if not _check(DistrictControl.holder(t, district)[0] == &"", "half the blocks is not the district"):
		return
	TerritorySystem.set_influence(t, all[half], &"player", 90.0)
	if not _check(DistrictControl.holder(t, district)[0] == &"player" and DistrictControl.held_by(t, &"player") == [district], "over half the blocks is the district"):
		return
	var old := TerritoryData.new()
	var sid: int = a["street"]
	old.cells[Vector2i(sid, Hoods.STREET_Y)] = {&"gang_0": 70.0}
	TerritoryData.migrate_streets(old)
	if not _check(not old.cells.keys().any(func(c: Vector2i) -> bool: return Hoods.is_street(c)) and TerritorySystem.get_influence(old, ka, &"gang_0") == 70.0, "a T2 street's hold moves onto its blocks"):
		return
	print("DISTRICTS_VERIFY: PASS")
	quit(0)

func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("DISTRICTS_VERIFY: FAIL - " + what)
		quit(1)
	return ok
