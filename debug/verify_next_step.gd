## NX1/TP1 validator: the next-step line points a new Street rat at the nearest
## fixer with a distance and a compass direction, puts an urgent need first and a
## job above everything; first-day tips show once each, in order, never while
## switched off, and which tips were seen is saved (the tip on screen is not).
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	var first := NextStep.line(w)
	print("new game: ", first)
	ok = _check(first.contains("Hustler") and first.contains("fixer") and first.contains(" m "), "a new player is pointed at a fixer") and ok
	ok = _check(NextStep.where(Vector2.ZERO, Vector2(0, -300)) == "300 m north" and NextStep.where(Vector2.ZERO, Vector2(50, 50)) == "71 m south-east", "compass: north is up, as on the map") and ok
	me.hunger = 0.1
	ok = _check(NextStep.line(w).contains("starving"), "a starving player is told to eat") and ok
	var fixer := NextStep.nearest_fixer(w, me.position)
	var offers := JobSystem.offers(w, state, fixer)
	JobSystem.take(w, state, offers[0])
	var job := NextStep.line(w)
	print("on a job: ", job)
	ok = _check(job.begins_with("Job: ") and job.contains("h left"), "a job comes first") and ok
	state.job = {}
	me.hunger = 1.0
	state.jobs_done = 1
	ok = _check(not NextStep.line(w).contains("fixer pays"), "after a first job the fixer hint goes") and ok
	# tips
	var tips := TipSystem.new(w)
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	state.tips_on = false
	tips.process_entities(players, 0.0, 600 + TipSystem.PHASE)
	ok = _check(state.tip_serial == 0, "no tips while switched off") and ok
	state.tips_on = true
	tips.process_entities(players, 0.0, 600 + TipSystem.PHASE)
	ok = _check(state.tips_seen == ["start"], "the welcome tip comes first") and ok
	tips.process_entities(players, 0.0, 660 + TipSystem.PHASE)
	ok = _check(state.tip_serial == 1, "tips wait their gap") and ok
	me.position = fixer.position + Vector2(3, 0)
	w.reindex_position(me.id)
	var t := 600 + int(TipSystem.GAP_S * SimClock.TICKS_PER_SECOND)
	t -= t % SimClock.TICKS_PER_SECOND
	tips.process_entities(players, 0.0, t + 60 + TipSystem.PHASE)
	print("tips seen: ", state.tips_seen, " | ", state.tip_text)
	ok = _check(state.tips_seen.has("fixer") and state.tip_serial == 2, "standing by a fixer brings the fixer tip") and ok
	var fields := SaveGame._fields(state)
	ok = _check(fields.has("tips_seen") and fields.has("tips_on") and not fields.has("tip_text"), "tips seen are saved, the tip on screen is not") and ok
	if ok:
		print("NEXT_STEP_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("NEXT_STEP_VERIFY: FAIL - ", what)
	return ok
