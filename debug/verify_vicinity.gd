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
	# INV7: container buttons and Zomboid's "Loot all".
	npc.position = Vector2(10, 10)
	st.inventory = {&"water": 1, &"chips": 2}
	Vicinity.drop(npc, st, &"water", 1)
	npc.position = Vector2(11.5, 10)
	Vicinity.drop(npc, st, &"chips", 2)
	var all := Vicinity.near(world, npc, st)
	ok = ok and Vicinity.sources(all) == ["ground"] and Vicinity.title_of("ground") == "Floor"
	ok = ok and Vicinity.only(all, "ground").size() == all.size() and Vicinity.only(all, "trunk").is_empty()
	ok = ok and Vicinity.key_of({"kind": "container", "cont": "stash"}) == "container:stash"
	ok = ok and Vicinity.take_all(world, st, Vicinity.only(all, "ground")).get("ok", false)
	ok = ok and st.inventory.get(&"water", 0) == 1 and st.inventory.get(&"chips", 0) == 2 and Vicinity.near(world, npc, st).is_empty()
	print("VICINITY_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
