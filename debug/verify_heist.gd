## HS1 validator: no score for a Street rat; a Hustler gets word of one;
## casing it reveals the guards and raises the take; starting before the
## window is refused; the work trips the alarm (the police head for the
## place) and finishes; getting far enough away unseen pays and makes the
## paper; walking off mid-job blows it; a lookout holds the alarm off longer.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var city := TestWorlds.city()
	SimNav.install(city, city.spawn, 900.0)
	await TestWorlds.wait_nav(self, [SimNav.active])
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	var t := SimClock.hours(30.0)
	w.tick = t
	ok = _check(not HeistSystem.offer(w, state, me, t) or state.rank >= 1, "a Street rat gets no score") and ok
	state.heist = {}
	state.rank = 1
	ok = _check(HeistSystem.offer(w, state, me, t, "store") and state.heist["stage"] == "rumour", "a Hustler gets word of a score") and ok
	var h := state.heist
	print("score: %s %s, $%d, %s, trouble %s" % [HeistSystem.KINDS[h["kind"]][0], h["where"], h["take"], HeistSystem.window_text(h), h["complication"]])
	h["complication"] = "quiet"
	var take := int(h["take"])
	me.position = (h["at"] as Vector2) + Vector2(10, 0)
	for i in 30:
		HeistSystem.advance(w, state, me, t, 1.0)
	ok = _check(h["stage"] == "cased" and h["known"] and int(h["take"]) > take, "casing it reveals the guards and raises the take") and ok
	me.position = h["at"]
	w.tick = int(h["from"]) - 10
	ok = _check(HeistSystem.start(w, state, me).get("reason", "") == "heist_not_yet", "too early is refused") and ok
	w.tick = int(h["from"]) + 10
	ok = _check(HeistSystem.start(w, state, me).get("ok", false) and h["stage"] == "working", "in the window the job starts") and ok
	var cops := w.find_system(CopAISystem) as CopAISystem
	for i in 60:
		HeistSystem.advance(w, state, me, w.tick, 1.0)
		if h["stage"] != "working":
			break
	ok = _check(h["alarm"] and h["stage"] == "getaway" and cops.hunters().all(func(x: Array) -> bool: return (x[1] as Vector2).distance_to(h["at"]) < 1.0), "the alarm trips (police head for the place) and the work finishes") and ok
	for c in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = c.get_component(ComponentNames.NPC)
		if n.is_cop:
			n.position = Vector2(-9000, -9000)
			w.reindex_position(n.id)
	var cash := me.cash
	me.position = (h["at"] as Vector2) + Vector2(HeistSystem.GETAWAY_M + 10.0, 0)
	w.reindex_position(me.id)
	HeistSystem.advance(w, state, me, w.tick, 1.0)
	print("paid: +$%d" % (me.cash - cash))
	ok = _check(state.heist.is_empty() and me.cash - cash >= take and state.news_today.any(func(n: Array) -> bool: return String(n[0]) == "heist_store"), "far away and unseen: paid, and it makes the paper") and ok

	HeistSystem.offer(w, state, me, w.tick - SimClock.hours(3.0), "store")
	state.heist["from"] = w.tick
	me.position = state.heist["at"]
	HeistSystem.start(w, state, me)
	me.position += Vector2(50, 0)
	HeistSystem.advance(w, state, me, w.tick, 1.0)
	ok = _check(state.heist.is_empty(), "walking off mid-job blows it") and ok

	var no_lookout := _alarm_after(w, state, me, false)
	var with_lookout := _alarm_after(w, state, me, true)
	print("alarm after %ds alone, %ds with a lookout" % [no_lookout, with_lookout])
	ok = _check(with_lookout > no_lookout, "a lookout holds the alarm off longer") and ok
	SimNav.uninstall()
	if ok:
		print("HEIST_VERIFY: PASS")
	quit(0 if ok else 1)

func _alarm_after(w: World, state: PlayerStateData, me: NPCData, lookout: bool) -> int:
	state.crew_ids.clear()
	if lookout:
		for e in w.get_entities_with_component(ComponentNames.NPC).values():
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if not (n.is_cop or n.is_dealer or n.is_down) and n.gang_id == &"" and n != me:
				n.is_crew = true
				n.crew_role = GanstoidEnums.CrewRole.LOOKOUT
				state.crew_ids.append(n.id)
				break
	state.heist = {}
	HeistSystem.offer(w, state, me, w.tick - SimClock.hours(3.0), "store")
	state.heist["from"] = w.tick
	state.heist["complication"] = "quiet"
	me.position = state.heist["at"]
	HeistSystem.start(w, state, me)
	for i in 100:
		HeistSystem.advance(w, state, me, w.tick, 1.0)
		if state.heist.get("alarm", false):
			return i + 1
	return 999

func _check(good: bool, what: String) -> bool:
	if not good:
		print("HEIST_VERIFY: FAIL - ", what)
	return good
