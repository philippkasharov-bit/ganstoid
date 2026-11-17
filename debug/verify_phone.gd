## PH1 validator: messages land in the inbox (capped); calling a fixer you
## have met (only one you have met) puts work offers on the phone; taking one
## starts the job; a rival's threat arrives as a message.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var phone := w.find_system(PhoneSystem) as PhoneSystem
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var ok := true
	for i in PhoneSystem.INBOX_MAX + 5:
		PhoneSystem.push(w, state, "Test", "message %d" % i)
	ok = _check(state.inbox.size() == PhoneSystem.INBOX_MAX and state.inbox[-1]["text"] == "message %d" % (PhoneSystem.INBOX_MAX + 4), "the inbox keeps the newest messages") and ok
	var fixer := NextStep.nearest_fixer(w, me.position)
	state.ui_phone = {"call": fixer.id}
	phone.process_entities(players, 0.0, 1)
	ok = _check(state.job_offers.is_empty(), "a fixer you haven't met doesn't pick up") and ok
	state.known[fixer.id] = "fixer"
	state.ui_phone = {"call": fixer.id}
	phone.process_entities(players, 0.0, 2)
	print("offers by phone: ", state.job_offers.map(func(j: Dictionary) -> String: return "%s $%d" % [j["text"], j["pay"]]))
	ok = _check(state.job_offers.size() >= 2, "calling a fixer you know gets offers") and ok
	state.ui_phone = {"take": 0}
	phone.process_entities(players, 0.0, 3)
	ok = _check(not state.job.is_empty() and state.job_offers.is_empty(), "taking one starts the job") and ok
	var rs := w.find_system(RivalSystem) as RivalSystem
	RivalSystem.ensure(w, state)
	var g: StringName = state.rivals.keys()[0]
	state.rivals[g]["grudge"] = RivalSystem.THREAT + 1.0
	var n := state.inbox.size()
	var t := SimClock.hours(30.0)
	t += RivalSystem.PHASE - t % RivalSystem.EVERY
	rs.process_entities(players, 0.0, t)
	print("newest message: ", state.inbox[-1])
	ok = _check(state.inbox[-1]["from"] == "Unknown number" and String(state.inbox[-1]["text"]).contains(state.rivals[g]["name"]), "a rival's threat arrives as a message") and ok
	if ok:
		print("PHONE_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("PHONE_VERIFY: FAIL - ", what)
	return good
