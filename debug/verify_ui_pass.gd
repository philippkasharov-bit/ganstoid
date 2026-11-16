## UI1-UI5 validator (logic behind the new HUD): the UI size is picked for
## the screen; the pager shows the next step and today's hustles; the prompt
## names what is in reach (someone down: Search; a person: Talk); a rank-up
## and a finished hustle each put a stamp up.
extends SceneTree

func _initialize() -> void:
	var ok := true
	ok = _check(UiSettings.auto_scale(720) == 1.0 and UiSettings.auto_scale(1080) == 1.15 and UiSettings.auto_scale(1440) == 1.3 and UiSettings.auto_scale(2160) == 1.5, "UI size picked for the screen") and ok
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	HustleSystem.roll(w, state, 1)
	var screen := PagerView.text_for(w, state)
	print(screen)
	ok = _check(screen.begins_with("> Next:") and screen.count("[ ]") == 3, "the pager shows the next step and three hustles") and ok
	var other: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_crew or n.is_down) and n.gang_id == &"":
			other = n
			break
	other.position = me.position + Vector2(1.5, 0)
	other.indoors = false
	w.reindex_position(other.id)
	var here := ContextPrompt.what_here(w, me)
	print("prompt: ", here.get("key"), "  ", here.get("text"))
	ok = _check(here.get("text", "").begins_with("Talk"), "a person in reach: Talk") and ok
	other.is_down = true
	ok = _check(ContextPrompt.what_here(w, me).get("text", "") == "Search their pockets", "someone down in reach: Search") and ok
	var stamps := state.stamp_serial
	me.cash = 5000
	var rank := w.find_system(RankSystem) as RankSystem
	rank.process_entities({PlayerFactory.PLAYER_ENTITY_ID: p}, 0.0, SimClock.hours(30.0) + RankSystem.PHASE_TICKS)
	print("rank now %s, stamp %s" % [RankSystem.name_of(state.rank), state.stamp])
	ok = _check(state.rank >= 1 and state.stamp_serial > stamps and String(state.stamp["sub"]) == "NEW RANK", "a new rank gets a stamp") and ok
	var h: Dictionary = state.hustles[0]
	var key: String = (HustleSystem.KINDS[h["kind"]][1] as Array)[0]
	for i in 3:
		HustleSystem.progress(w, state, key, 40)
	ok = _check(state.stamp["text"] == "HUSTLE DONE", "a finished hustle gets a stamp") and ok
	if ok:
		print("UI_PASS_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("UI_PASS_VERIFY: FAIL - ", what)
	return good
