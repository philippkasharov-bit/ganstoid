## UI9: DayZ-style status: colour steps, trend arrows, problem notices, best item.
extends SceneTree

func _initialize() -> void:
	var npc := NPCData.new()
	var state := PlayerStateData.new()
	var ok := Moodles.notices(npc, state).is_empty()   # nothing wrong: no notices
	ok = ok and Moodles.level_of(0.9) == 0 and Moodles.level_of(0.4) == 1 and Moodles.level_of(0.2) == 2 and Moodles.level_of(0.05) == 3
	ok = ok and Moodles.value(npc, "calm") == 1.0
	ok = ok and Moodles.arrows(-0.6) == -1 and Moodles.arrows(-1.5) == -2 and Moodles.arrows(5.0) == 3 and Moodles.arrows(0.01) == 0
	npc.bleeding = true
	state.law_tier = 2
	var names := Moodles.notices(npc, state).map(func(n: Array) -> String: return n[1])
	ok = ok and names == ["Bleeding", "Wanted"]
	state.inventory = {&"chips": 1, &"burrito": 2, &"water": 1}
	ok = ok and Moodles.best_item(state, "food") == &"burrito" and Moodles.best_item(state, "medical") == &""
	ok = ok and Moodles.gauge_colour(0.0).r > 0.8 and Moodles.gauge_colour(1.0).g > Moodles.gauge_colour(1.0).r
	var e := Moodles.gauge_colour(1.0, "fatigue")
	ok = ok and e.r > 0.9 and e.g > 0.8 and e.b < 0.4 and Moodles.gauge_colour(0.0, "fatigue").r > 0.8
	print("MOODLES_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
