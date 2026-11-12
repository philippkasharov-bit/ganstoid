## UI6: moodles appear at the right needs and grow with them.
extends SceneTree

func _initialize() -> void:
	var npc := NPCData.new()
	var state := PlayerStateData.new()
	var ok := Moodles.list(null, npc, state).is_empty()   # fed, rested, unhurt, clean: nothing shows
	npc.hunger = 0.4
	npc.health = 0.7
	var shown := Moodles.list(null, npc, state)
	ok = ok and shown.size() == 2 and shown[0]["name"] == "Hungry" and shown[0]["level"] == 1 and shown[0]["value"] == "40%" and shown[1]["name"] == "Hurt"
	npc.hunger = 0.02
	npc.bleeding = true
	state.law_tier = 2
	shown = Moodles.list(null, npc, state)
	var names := shown.map(func(m: Dictionary) -> String: return m["name"])
	ok = ok and shown[0]["level"] == 4 and names.has("Bleeding") and names.has("Wanted")
	state.inventory = {&"chips": 1, &"burrito": 2, &"water": 1}
	ok = ok and Moodles.best_item(state, "food") == &"burrito" and Moodles.best_item(state, "medical") == &""
	print("MOODLES_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
