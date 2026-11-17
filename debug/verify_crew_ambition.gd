## CA1 validator: a greedy member asks for a wage (paid each morning once
## agreed, and unpaid they sour); a climber asks for a corner, and as a
## lieutenant their corner pays more; a lieutenant gone sour walks off with
## a slice of your cash; a rat with you under heat gets you a warning, and
## left alone walks and becomes a witness for your trial; scared straight
## they won't testify; refusing someone already sour loses them; a loyal one
## sends a gift; and every nature gets rolled for a new member.
extends SceneTree

var w: World
var me: NPCData
var state: PlayerStateData
var tick := 0

func _initialize() -> void:
	w = World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	me = p.get_component(ComponentNames.NPC)
	state = p.get_component(ComponentNames.PLAYER_STATE)
	tick = SimClock.hours(30.0)
	var ok := true
	var ppl := _people(8)
	# greedy: a wage
	var g := _join(ppl[0], &"greedy", 0.5)
	ok = _check(_until(func() -> bool: return _ask_of(g.id) == "raise"), "a greedy member asks for a wage") and ok
	var inbox_text: String = state.inbox[-1]["text"]
	CrewAmbitionSystem.answer(w, me, state, g.id, "pay")
	me.cash = 500
	_day()
	ok = _check(int(state.crew_wages.get(g.id, 0)) == CrewAmbitionSystem.WAGE_STEP and me.cash == 500 - CrewAmbitionSystem.WAGE_STEP, "agreed: $%d paid next morning (\"%s\")" % [CrewAmbitionSystem.WAGE_STEP, inbox_text]) and ok
	var l := g.loyalty
	me.cash = 0
	_day()
	ok = _check(g.loyalty < l, "can't pay: they sour (%.2f -> %.2f)" % [l, g.loyalty]) and ok
	_leave(g)
	# climber: a corner, then the lieutenant's bonus
	var c := _join(ppl[1], &"climber", 0.7)
	ok = _check(_until(func() -> bool: return _ask_of(c.id) == "corner"), "a climber asks for a corner") and ok
	CrewAmbitionSystem.answer(w, me, state, c.id, "promote")
	c.crew_earnings = 100
	var dirty := state.dirty_cash
	var paid := CrewLoyaltySystem.pay_out_earnings(w, c)
	ok = _check(c.crew_rank == 1 and paid == 150 - 15 and state.dirty_cash == dirty + paid, "a lieutenant's corner pays half again ($%d)" % paid) and ok
	# the lieutenant goes sour and walks, with a friend and a slice
	var friend := _join(ppl[2], &"loyal", 0.3)
	c.loyalty = 0.1
	me.cash = 1000
	ok = _check(_until(func() -> bool: return not state.crew_ids.has(c.id)), "a sour lieutenant makes a move") and ok
	ok = _check(me.cash == 850 and not state.crew_ids.has(friend.id) and state.stamp.get("text", "") == "BETRAYED", "they take 15%% of your cash and a friend (cash %d)" % me.cash) and ok
	# a rat, with heat on you
	var r := _join(ppl[3], &"rat", 0.3)
	state.case_evidence = 10.0
	ok = _check(_until(func() -> bool: return _ask_of(r.id) == "rat"), "a rat, with heat on you: someone warns you") and ok
	ok = _check(String(state.inbox[-1]["text"]).contains("talking to a cop"), "the warning is on the phone") and ok
	var case_before := state.case_evidence
	tick += SimClock.day_ticks + 10
	_day()
	ok = _check(not state.crew_ids.has(r.id) and state.case_evidence > case_before and MemorySystem.feel_of(state, r.id) <= -0.9, "left alone, they walk and talk (case %.0f -> %.0f)" % [case_before, state.case_evidence]) and ok
	ok = _check(CourtSystem.witnesses(w, state).has(r.id) and CourtSystem.stand_of(w, state, r.id) == "talks", "and they're a witness at your trial") and ok
	# scared straight: no testimony
	var r2 := _join(ppl[4], &"rat", 0.3)
	_until(func() -> bool: return _ask_of(r2.id) == "rat")
	CrewAmbitionSystem.answer(w, me, state, r2.id, "scare")
	ok = _check(state.crew_ids.has(r2.id) and CourtSystem.stand_of(w, state, r2.id) == "scared", "scared straight: still crew, won't testify") and ok
	_leave(r2)
	# refusing someone already sour loses them
	var s := _join(ppl[5], &"greedy", 0.3)
	_until(func() -> bool: return _ask_of(s.id) == "raise")
	CrewAmbitionSystem.answer(w, me, state, s.id, "refuse")
	ok = _check(not state.crew_ids.has(s.id), "refuse someone already sour and they quit") and ok
	# a loyal one's gift
	state.case_evidence = 0.0
	var lo := _join(ppl[6], &"loyal", 0.95)
	var cash0 := me.cash
	ok = _check(_until(func() -> bool: return me.cash > cash0), "a loyal member sends a gift ($%d)" % (me.cash - cash0)) and ok
	_leave(lo)
	# a new member gets a nature
	var nw := _join(ppl[7], &"", 0.5)
	_day()
	ok = _check(CrewAmbitionSystem.NATURES.has(nw.ambition), "a new member gets a nature (%s)" % nw.ambition) and ok
	if ok:
		print("CREW_AMBITION_VERIFY: PASS")
	quit(0 if ok else 1)

func _join(n: NPCData, nature: StringName, loyalty: float) -> NPCData:
	n.is_crew = true
	n.ambition = nature
	n.loyalty = loyalty
	n.crew_days = 5
	n.crew_rank = 0
	n.fear = 0.0
	state.crew_ids.append(n.id)
	return n

func _leave(n: NPCData) -> void:
	CrewAmbitionSystem._out(w, state, n)

func _day() -> void:
	tick += SimClock.day_ticks
	w.tick = tick
	CrewAmbitionSystem.new_day(w, me, state, tick)

## Days pass until `cond` holds (at most 40).
func _until(cond: Callable) -> bool:
	for i in 40:
		if cond.call():
			return true
		_day()
	return cond.call()

func _ask_of(id: StringName) -> String:
	for a in state.crew_asks:
		if a["id"] == id:
			return a["kind"]
	return ""

func _people(count: int) -> Array:
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
		print("CREW_AMBITION_VERIFY: FAIL - " + what)
	return good
