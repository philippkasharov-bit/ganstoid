## CT1 validator: a thin case is still a night in the cells; a real one is
## a charge (searched, a trial in two days, the people who remember you as
## witnesses, a message and the pager line). A witness you scared stays home,
## one you paid forgets; a lawyer takes points off. On the day: the court
## hears who talks and finds you guilty (days inside) or not (free); a
## broken trial from a bad save is dropped.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	w.tick = SimClock.hours(36.0)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var court := w.find_system(CourtSystem) as CourtSystem
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var ok := true
	state.case_evidence = CaseSystem.PRISON_FROM - 1.0
	ok = _check(not CourtSystem.charge(w, me, state), "a thin case is no trial") and ok
	var ppl := _people(w, me, 4)
	var robbed: NPCData = ppl[0]
	var saw: NPCData = ppl[1]
	var paid: NPCData = ppl[2]
	var scared: NPCData = ppl[3]
	for n in ppl:
		n.fear = 0.0
	MemorySystem.remember(w, state, robbed.id, "robbed")
	MemorySystem.remember(w, state, saw.id, "saw_crime")
	MemorySystem.remember(w, state, paid.id, "saw_crime")
	MemorySystem.remember(w, state, scared.id, "robbed")
	state.case_evidence = 50.0
	Wallet.earn_dirty(w, 300)
	var inbox := state.inbox.size()
	ok = _check(CourtSystem.charge(w, me, state), "a real case is a charge") and ok
	var t := state.trial
	ok = _check(int(t["at"]) == w.tick + 2 * SimClock.day_ticks and state.case_evidence == 0.0 and state.dirty_cash == 0, "trial in two days; the case moved to court; dirty cash seized") and ok
	ok = _check(t["witnesses"].size() == 4 and t["witnesses"][0] in [robbed.id, scared.id], "the four who remember you are the witnesses, the angriest first") and ok
	ok = _check(state.inbox.size() == inbox + 1 and state.stamp.get("text", "") == "CHARGED", "a message and a stamp") and ok
	print("pager: ", NextStep.line(w))
	ok = _check(NextStep.line(w).begins_with("Trial in 48h: 4 witnesses will talk"), "the pager says what's coming") and ok
	# working on the witnesses
	me.cash += 1000   # clean
	TalkSystem.pay_off(w, me, paid)
	TalkSystem.pay_off(w, me, paid)
	TalkSystem.threaten(w, me, scared)
	TalkSystem.threaten(w, me, scared)
	ok = _check(CourtSystem.stand_of(w, state, paid.id) == "bought" and CourtSystem.stand_of(w, state, scared.id) == "scared" and CourtSystem.stand_of(w, state, robbed.id) == "talks", "paid forgets, scared stays home, the robbed one talks") and ok
	var before := CourtSystem.score(w, state)
	ok = _check(CourtSystem.lawyer(w, state).get("ok", false) and is_equal_approx(CourtSystem.score(w, state), maxf(0.0, before - CourtSystem.LAWYER_CUT)), "a lawyer takes %d off (%.0f -> %.0f)" % [CourtSystem.LAWYER_CUT, before, CourtSystem.score(w, state)]) and ok
	# the day: guilty if it's still over the line
	var s := CourtSystem.score(w, state)
	_sit(w, court, players, int(t["at"]))
	print("verdict: ", state.verdict)
	var lines: Array = state.verdict.get("lines", [])
	ok = _check(state.trial.is_empty() and lines.size() == 4, "the court sits on the day and hears all four") and ok
	ok = _check(lines.any(func(l: Array) -> bool: return String(l[1]).contains("Too scared")) and lines.any(func(l: Array) -> bool: return String(l[1]).contains("don't remember")), "the court window shows who stayed away and who forgot") and ok
	ok = _check(state.verdict["guilty"] == (s >= CourtSystem.GUILTY_AT) and (state.prison_until_tick > 0) == (s >= CourtSystem.GUILTY_AT), "the verdict follows the case (%.0f, %s)" % [s, "guilty" if state.verdict["guilty"] else "free"]) and ok
	state.ui_court = "close"
	_sit(w, court, players, w.tick + 1)
	ok = _check(state.verdict.is_empty(), "Close clears the court window") and ok
	# a second case where every witness is dealt with: free
	state.prison_until_tick = 0
	me.indoors = false
	state.case_evidence = 40.0
	CourtSystem.charge(w, me, state)
	for id in state.trial["witnesses"]:
		var n: NPCData = w.entities[id].get_component(ComponentNames.NPC)
		n.fear = 1.0
	_sit(w, court, players, int(state.trial["at"]))
	ok = _check(not state.verdict.get("guilty", true) and state.prison_until_tick == 0 and CourtSystem.score(w, state) == 0.0, "with every witness too scared, you walk (case %.0f)" % (40.0 * CourtSystem.FILE_WEIGHT)) and ok
	# a broken trial from a bad save
	state.verdict = {}
	state.trial = {"at": "soon", "witnesses": 3}
	_sit(w, court, players, w.tick + 1)
	ok = _check(state.trial.is_empty() and state.verdict.is_empty(), "a broken trial is dropped, not crashed on") and ok
	if ok:
		print("COURT_VERIFY: PASS")
	quit(0 if ok else 1)

## The court's pass on the first aligned tick at or after `at`.
func _sit(w: World, court: CourtSystem, players: Dictionary, at: int) -> void:
	at += posmod(CourtSystem.PHASE - at, CourtSystem.EVERY)
	w.tick = at
	court.process_entities(players, 0.0, at)

func _people(w: World, me: NPCData, count: int) -> Array:
	var out := []
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_fixer or n.is_down) and n.gang_id == &"":
			out.append(n)
			if out.size() == count:
				break
	return out

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("COURT_VERIFY: FAIL - " + what)
	return good
