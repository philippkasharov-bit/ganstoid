## INV4: drop, merge, pick up with room rules, car trunk only when you may open it.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var npc := NPCData.new()
	npc.position = Vector2(10, 10)
	var st := PlayerStateData.new()
	st.inventory = {&"bandage": 4, &"knife": 1}
	st.weapon = &"knife"
	var ok: bool = Vicinity.drop(npc, st, &"bandage", 2).get("ok", false) and st.inventory[&"bandage"] == 2
	ok = ok and Vicinity.drop(npc, st, &"bandage", 1).get("ok", false) and st.ground.size() == 1 and st.ground[0]["n"] == 3   # merged
	Vicinity.drop(npc, st, &"knife", 1)
	ok = ok and st.weapon == &"fists" and not st.inventory.has(&"knife")   # dropped what was in hand
	var near := Vicinity.near(world, npc, st)
	ok = ok and near.size() == 2
	ok = ok and Vicinity.take(world, st, near[0], 999).get("ok", false) and st.inventory[&"bandage"] == 4
	npc.position = Vector2(30, 30)
	ok = ok and Vicinity.near(world, npc, st).is_empty()   # walked away: out of reach
	print("VICINITY_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
