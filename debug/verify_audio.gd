## AU1 validator: every sound loads (the loops loop); the buses exist and
## the volume settings move them; day traffic by day and crickets by night;
## walking makes steps; a near shot is sharp and a far one dull; cash, a new
## rank, a phone message, a StreetTalk line and a button each make their
## sound; getting in a car starts the engine and the radio, getting out stops
## them; and none of it touches the sim's own random numbers.
extends SceneTree

func _initialize() -> void:
	var ok := true
	for name in AudioBank.LOOPS + AudioBank.ONE_SHOTS:
		var s := AudioBank.stream(name)
		if s == null or s.get_length() < 0.04:
			ok = _check(false, "the sound %s loads" % name) and ok
		elif AudioBank.LOOPS.has(name) and (s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_end <= 0):
			ok = _check(false, "%s loops" % name) and ok
	ok = _check(true, "%d sounds load, %d of them loop" % [AudioBank.LOOPS.size() + AudioBank.ONE_SHOTS.size(), AudioBank.LOOPS.size()]) and ok
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var rng_before := w.runtime_rng.state
	var a := AudioDirector.new()
	a.world = w
	root.add_child(a)
	await process_frame   # _ready runs once the tree is up
	ok = _check(AudioServer.get_bus_index(&"Music") != -1 and AudioServer.get_bus_index(&"Effects") != -1, "the Music and Effects buses exist") and ok
	w.tick = SimClock.hours(13.0)
	_run(a, 40)
	print("1 pm: day %.2f night %.2f crowd %.2f" % [a.ambience_level("day"), a.ambience_level("night"), a.ambience_level("crowd")])
	ok = _check(a.ambience_level("day") > 0.3 and a.ambience_level("night") < 0.05, "by day you hear the traffic, not crickets") and ok
	w.tick = SimClock.hours(25.0)
	_run(a, 40)
	print("1 am: day %.2f night %.2f" % [a.ambience_level("day"), a.ambience_level("night")])
	ok = _check(a.ambience_level("night") > 0.5 and a.ambience_level("day") < 0.05, "at night the crickets, not the traffic") and ok
	a.played.clear()
	for i in 20:
		me.position += Vector2(0.15, 0.0)   # 1.5 m/s, a walk
		a._process(0.1)
	var steps := a.played.filter(func(s: String) -> bool: return s.begins_with("step_")).size()
	ok = _check(steps >= 3 and steps <= 5, "walking 3 m makes %d steps" % steps) and ok
	a.played.clear()
	w.event_bus.emit(GanstoidEvents.GUNSHOT, {"position": me.position + Vector2(10, 0), "heard_m": 300.0, "tick": w.tick})
	w.event_bus.emit(GanstoidEvents.GUNSHOT, {"position": me.position + Vector2(200, 0), "heard_m": 300.0, "tick": w.tick})
	ok = _check(a.played == ["shot", "shot_far"], "a near shot is sharp, a far one dull") and ok
	ok = _check(w.runtime_rng.state == rng_before, "sound never draws from the sim's random numbers") and ok
	a.played.clear()
	me.cash += 100
	_run(a, 1)
	ok = _check(a.played.has("ui_cash"), "cash in rings the till") and ok
	StampView.put(state, "HUSTLER", "NEW RANK")
	_run(a, 1)
	ok = _check(a.played.has("ui_rank"), "a new rank gets its fanfare") and ok
	PhoneSystem.push(w, state, "Test", "yo")
	_run(a, 1)
	ok = _check(a.played.has("phone_buzz"), "a message buzzes the phone") and ok
	StreetTalk.say_key(w, state, "locked")
	_run(a, 1)
	ok = _check(a.played.has("rattle"), "a locked door rattles") and ok
	var b := Button.new()
	root.add_child(b)
	await process_frame
	b.pressed.emit()
	ok = _check(a.played.has("ui_click"), "a button clicks") and ok
	var car_id := &""
	for e in w.get_entities_with_component(ComponentNames.VEHICLE).values():
		car_id = e.id
		break
	state.vehicle_id = car_id
	_run(a, 2)
	ok = _check(a.played.has("radio_1") and a._radio.stream != null and a._engine.stream != null, "in a car: the engine and the radio") and ok
	state.vehicle_id = &""
	_run(a, 2)
	ok = _check(not a._radio.playing and not a._engine.playing, "out of the car they stop") and ok
	var music := UiSettings.volume("Music")
	UiSettings.set_volume("Music", 0.5)
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
	var next := UiSettings.cycle_volume("Music")
	ok = _check(absf(db - linear_to_db(0.5)) < 0.01 and is_equal_approx(next, 0.75), "the Music volume setting moves the bus (50%, then 75%)") and ok
	UiSettings.set_volume("Music", music)
	if ok:
		print("AUDIO_VERIFY: PASS")
	quit(0 if ok else 1)

func _run(a: AudioDirector, frames: int) -> void:
	for i in frames:
		a._process(0.1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("AUDIO_VERIFY: FAIL - " + what)
	return good
