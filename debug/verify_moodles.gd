## UI24: Zomboid moodles: none when all is well, level names by severity,
## bleeding / wanted problems, a "Well Fed" good moodle, best item to use.
extends SceneTree

func _initialize() -> void:
	var npc := NPCData.new()
	npc.hunger = 0.8
	var state := PlayerStateData.new()
	var ok := Moodles.list(npc, state).is_empty()   # fine: nothing on screen
	npc.hunger = 0.4
	var shown := Moodles.list(npc, state)
	ok = ok and shown.size() == 1 and shown[0][1] == "Peckish" and shown[0][2] == 1 and not shown[0][3]
	npc.hunger = 0.02
	ok = ok and Moodles.list(npc, state)[0][1] == "Starving"
	npc.hunger = 0.99
	ok = ok and Moodles.list(npc, state)[0][1] == "Well Fed" and Moodles.list(npc, state)[0][3]   # a good one
	npc.bleeding = true
	state.law_tier = 2
	var names := Moodles.list(npc, state).map(func(m: Array) -> String: return m[1])
	ok = ok and names.has("Bleeding") and names.has("Wanted")
	state.inventory = {&"chips": 1, &"burrito": 2, &"water": 1}
	ok = ok and Moodles.best_item(state, "food") == &"burrito" and Moodles.best_item(state, "medical") == &""
	print("MOODLES_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
