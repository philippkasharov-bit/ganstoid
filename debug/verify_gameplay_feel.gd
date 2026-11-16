## GP1/GP2/LT3 validator (Phil's play notes): you run faster than someone
## fleeing you, a full breath lasts about half a minute of running, a small cut
## stops bleeding by itself while a deep one needs a bandage, someone running
## from you stops when you catch them, and a knocked-out person's pockets
## (their cash and what they carry) show in Nearby and can be emptied.
extends SceneTree

func _initialize() -> void:
	var ok := true
	ok = _check(PlayerInputSystem.RUN_SPEED > SimUnits.JOG + 1.0, "you run faster than a fleeing jog") and ok
	var st := PlayerStateData.new()
	st.endurance = 1.0
	var secs := 0.0
	while not st.winded and secs < 120.0:
		Stamina.update(st, true, true, 0.1)
		secs += 0.1
	print("running from full breath: %.0f s" % secs)
	ok = _check(secs >= 25.0, "a full breath lasts 25 s of running or more") and ok
	BodyParts.ensure(st)
	st.body["l_forearm"]["wound"] = "laceration"
	st.body["l_forearm"]["bleeding"] = true
	st.body["torso_lower"]["wound"] = "deep wound"
	st.body["torso_lower"]["bleeding"] = true
	for i in 30:
		BodyParts.heal(st, BodyParts.CLOT_DAYS / 20.0)
	ok = _check(not st.body["l_forearm"]["bleeding"] and st.body["torso_lower"]["bleeding"], "a cut clots by itself, a deep wound keeps bleeding") and ok
	ok = _check(NeedsSystem.HUNGER_PER_DAY <= 0.35 and NeedsSystem.THIRST_PER_DAY <= 0.6, "hunger and thirst at the gentler rates") and ok

	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var city := TestWorlds.city()
	SimNav.install(city, city.spawn, 200.0)
	await TestWorlds.wait_nav(self, [SimNav.active])
	var me: NPCData = w.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var state: PlayerStateData = w.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var sched := w.find_system(NPCScheduleSystem) as NPCScheduleSystem
	var runner := _someone(w, me)
	runner.position = me.position + Vector2(1.2, 0)
	w.reindex_position(runner.id)
	sched.street.step_out(runner)
	sched.street.start_trip(runner, [], me.position + Vector2(200, 0), SimUnits.JOG)
	var before := runner.position
	for t in 30:
		sched.street.step_all(1.0 / 60.0, 1000 + t, me.position)
	ok = _check(runner.position.distance_to(before) < 0.05, "someone running from you stops when you catch them") and ok

	var victim := _someone(w, me)
	victim.position = me.position + Vector2(1.0, 0)
	victim.cash = 37
	victim.is_down = true
	w.reindex_position(victim.id)
	var near := Vicinity.near(w, me, state)
	var cash_src: Dictionary = {}
	var items := 0
	for src in near:
		if src["kind"] == "body":
			items += 1
			if src["id"] == &"cash":
				cash_src = src
	print("on the body: %d piles, title %s" % [items, Vicinity.title_of(Vicinity.key_of(cash_src)) if not cash_src.is_empty() else "-"])
	ok = _check(not cash_src.is_empty() and int(cash_src["n"]) == 37, "a downed person's cash shows in Nearby") and ok
	var had := me.cash
	if not cash_src.is_empty():
		Vicinity.take(w, state, cash_src, 37)
	ok = _check(me.cash == had + 37 and victim.cash == 0, "taking it moves the cash to you") and ok
	victim.pockets_rolled = false
	victim.pockets = {}
	Vicinity._roll_pockets(victim)
	var first := victim.pockets.duplicate()
	victim.pockets_rolled = false
	Vicinity._roll_pockets(victim)
	ok = _check(victim.pockets == first, "pockets roll the same each time (seeded)") and ok
	SimNav.uninstall()
	if ok:
		print("GAMEPLAY_FEEL_VERIFY: PASS")
	quit(0 if ok else 1)

func _someone(w: World, me: NPCData) -> NPCData:
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_down or n.is_fixer):
			return n
	return null

func _check(good: bool, what: String) -> bool:
	if not good:
		print("GAMEPLAY_FEEL_VERIFY: FAIL - ", what)
	return good
