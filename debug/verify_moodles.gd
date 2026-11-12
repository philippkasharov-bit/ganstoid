## UI6: moodles appear at the right needs and grow with them.
extends SceneTree

func _initialize() -> void:
	var npc := NPCData.new()
	var state := PlayerStateData.new()
	var ok := Moodles.list(null, npc, state).is_empty()   # fed, rested, unhurt, clean: nothing shows
	npc.hunger = 0.4
	npc.health = 0.7
	var shown := Moodles.list(null, npc, state)
	ok = ok and shown.size() == 2 and shown[0][1] == "Hungry" and shown[0][2] == 1 and shown[1][1] == "Hurt"
	npc.hunger = 0.02
	npc.bleeding = true
	state.law_tier = 2
	shown = Moodles.list(null, npc, state)
	var names := shown.map(func(m: Array) -> String: return m[1])
	ok = ok and shown[0][2] == 4 and names.has("Bleeding") and names.has("Wanted")
	print("MOODLES_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
