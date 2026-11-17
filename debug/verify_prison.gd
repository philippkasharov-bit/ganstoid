## JL1 validator: inside, keeping your head down takes a day off every few
## days; the yard pays; an appeal with clean money cuts days (without it, it
## doesn't); a failed escape adds days and a good one gets you out wanted;
## your crew's loyalty slips each day (less with a crib to hang out in);
## connections made inside raise gang standing and line up a score on release.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	var t := SimClock.hours(30.0)
	w.tick = t
	state.case_evidence = 120.0
	var days := CaseSystem.sentence(w, me, state)
	print("sentenced: %d days" % days)
	ok = _check(days >= 2 and state.prison_until_tick > t, "sentenced") and ok
	var until := state.prison_until_tick
	state.prison_choice = "head_down"
	for i in PrisonSystem.GOOD_DAYS:
		PrisonSystem.day_inside(w, state, me, t)
	ok = _check(state.prison_until_tick == until - SimClock.day_ticks, "good behaviour takes a day off") and ok
	var cash := me.cash
	state.prison_choice = "yard"
	PrisonSystem.day_inside(w, state, me, t)
	ok = _check(me.cash > cash, "the yard pays") and ok
	until = state.prison_until_tick
	me.cash = 0
	state.dirty_cash = 0
	state.prison_choice = "appeal"
	PrisonSystem.day_inside(w, state, me, t)
	ok = _check(state.prison_until_tick == until, "no money, no appeal") and ok
	me.cash = 1000
	state.prison_choice = "appeal"
	PrisonSystem.day_inside(w, state, me, t)
	ok = _check(state.prison_until_tick == until - PrisonSystem.APPEAL_DAYS * SimClock.day_ticks and me.cash == 1000 - PrisonSystem.APPEAL_COST, "an appeal with clean money cuts days") and ok
	var mate: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_dealer) and n.gang_id == &"":
			mate = n
			break
	mate.is_crew = true
	mate.loyalty = 0.8
	state.crew_ids.append(mate.id)
	state.prison_choice = "connections"
	PrisonSystem.day_inside(w, state, me, t)
	var slipped := 0.8 - mate.loyalty
	state.crib = CribSystem.HANGOUT_TIER
	mate.loyalty = 0.8
	PrisonSystem.day_inside(w, state, me, t)
	print("crew loyalty slips %.2f a day, %.2f with a crib" % [slipped, 0.8 - mate.loyalty])
	ok = _check(slipped > 0.0 and 0.8 - mate.loyalty < slipped, "the crew slips, less with a crib") and ok
	w.runtime_rng.seed = 1
	var fails := 0
	var outs := 0
	for i in 40:
		var before := state.prison_until_tick
		state.prison_choice = "escape"
		PrisonSystem.day_inside(w, state, me, t)
		if state.prison_until_tick == t:
			outs += 1
			state.prison_until_tick = before
			state.law_tier = GanstoidEnums.LawTier.CLEAN
		elif state.prison_until_tick > before:
			fails += 1
	print("40 escape tries at %d%%: %d out, %d caught" % [roundi(PrisonSystem.escape_odds(w, state) * 100.0), outs, fails])
	ok = _check(outs > 0 and fails > 0, "escapes can work and can fail") and ok
	state.rank = 1
	state.heist = {}
	state.prison_connections = 2
	state.prison_until_tick = 0
	var ps := w.find_system(PrisonSystem) as PrisonSystem
	ps.process_entities({PlayerFactory.PLAYER_ENTITY_ID: p}, 0.0, t + 5)
	print("out: standing %s, score lined up %s" % [state.gang_standing.values(), not state.heist.is_empty()])
	ok = _check(state.prison_connections == 0 and state.gang_standing.values().all(func(v: float) -> bool: return v > 0.5), "connections pay off when you're out") and ok
	if ok:
		print("PRISON_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("PRISON_VERIFY: FAIL - ", what)
	return good
