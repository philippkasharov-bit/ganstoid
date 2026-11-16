## DH1/NP1 validator: three hustles arrive each morning (the same after a
## reload), they move as you play and pay out when done, and an unfinished
## one is gone after its deadline. What you do makes the next morning's
## paper: a store robbery is the headline, with the hood it happened in; a
## quiet night still prints a paper; hustles and the paper are saved.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var hs := HustleSystem.new(w)
	var ns := NewsSystem.new(w)
	var ok := true
	var t := SimClock.hours(24.0 + 8.0)
	t -= t % SimClock.TICKS_PER_SECOND
	ns.process_entities(players, 0.0, t + NewsSystem.PHASE)   # first look: a new life gets no paper yet
	hs.process_entities(players, 0.0, t + HustleSystem.PHASE)
	print("hustles: ", state.hustles.map(func(h: Dictionary) -> String: return HustleSystem.line(w, h)))
	ok = _check(state.hustles.size() == 3 and state.paper.is_empty(), "three hustles in the morning, no paper on day one") and ok
	var again := state.hustles.duplicate(true)
	HustleSystem.roll(w, state, state.hustle_day)
	ok = _check(state.hustles == again, "the same three after a reload") and ok
	var h: Dictionary = state.hustles[0]
	var key: String = (HustleSystem.KINDS[h["kind"]][1] as Array)[0]
	var cash := me.cash
	for i in 3:
		StreetTalk.say(w, state, {"ok": true, "effect": key, "amount": 40})
	print("after doing it: %s, cash +%d" % [HustleSystem.line(w, h), me.cash - cash])
	ok = _check(h["done"] and me.cash - cash >= int(h["pay"]), "a finished hustle pays") and ok
	StreetTalk.say(w, state, {"ok": true, "effect": "robbery", "taken": 180})
	var late := int(state.hustles[1]["deadline"]) + SimClock.TICKS_PER_SECOND
	late -= late % SimClock.TICKS_PER_SECOND
	if not state.hustles[1]["done"]:
		hs.process_entities(players, 0.0, late + HustleSystem.PHASE)
		ok = _check(state.hustles.size() == 2, "a missed hustle is gone after its deadline") and ok
	var next := t + SimClock.hours(24.0)
	ns.process_entities(players, 0.0, next + NewsSystem.PHASE)
	print("paper: %s / %s" % [state.paper.get("headline"), state.paper.get("lead")])
	ok = _check(String(state.paper.get("headline", "")).begins_with("STORE HELD UP IN") and String(state.paper.get("lead", "")).contains("$180"), "the robbery is the headline") and ok
	ok = _check(state.news_today.is_empty() and state.paper_serial == 1, "the night's notes went to print") and ok
	ns.process_entities(players, 0.0, next + SimClock.hours(24.0) + NewsSystem.PHASE)
	ok = _check(state.paper.get("headline", "") == "QUIET NIGHT IN THE CITY" and state.paper_serial == 2, "a quiet night still prints") and ok
	var fields := SaveGame._fields(state)
	ok = _check(fields.has("hustles") and fields.has("paper") and fields.has("news_today"), "hustles and the paper are saved") and ok
	if ok:
		print("HUSTLES_PAPER_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("HUSTLES_PAPER_VERIFY: FAIL - ", what)
	return good
