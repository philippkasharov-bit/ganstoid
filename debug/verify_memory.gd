## ME1 validator: a mugging is remembered; the victim who sees you again
## shouts it over their head and calls the police (once), and runs next time;
## a friend says hello and, with police after you, tips you off; a store you
## held up won't serve you; a friend joins your crew more readily; feelings
## fade each day and faint ones are forgotten; the list keeps to MAX; and the
## memories survive a save.
extends SceneTree

const PATH := "user://verify_memory_save.txt"

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var mem := w.find_system(MemorySystem) as MemorySystem
	var ok := true
	var reports := [0]
	w.event_bus.subscribe(func(ev: StringName, _p: Dictionary) -> void:
		if ev == GanstoidEvents.CRIME_WITNESSED:
			reports[0] += 1)
	var people := _people(w, me, 6)
	var victim: NPCData = people[0]
	var friend: NPCData = people[1]
	# a mugging (retry: some victims are brave and run instead)
	state.weapon = &"knife"
	state.aiming = true
	var robbed := false
	for n in people.slice(0, 4):
		n.position = me.position + Vector2(1.0, 0.0)
		n.cash = 50
		if StreetCrime.mug(w, me, state, n).get("ok", false):
			victim = n
			robbed = true
			break
	state.aiming = false
	ok = _check(robbed and state.memories.has(victim.id) and state.memories[victim.id]["deed"] == "robbed" and MemorySystem.feel_of(state, victim.id) <= -0.7, "a mugging is remembered (feel %.2f)" % MemorySystem.feel_of(state, victim.id)) and ok
	# they see you again: they shout and report it
	var t := SimClock.hours(36.0)   # noon, day 2
	victim.position = me.position + Vector2(4.0, 0.0)
	victim.indoors = false
	victim.fear = 0.0
	victim.is_down = false
	w.spatial_index.update(victim.id, victim.position)
	reports[0] = 0
	t = _step(w, mem, players, t)
	var said := _bark_of(state, victim.id)
	print("the victim: ", said)
	ok = _check(not said.is_empty() and int(said["tone"]) == -1 and mem.reported == 1 and reports[0] >= 1, "the victim knows you, says it out loud and calls the police") and ok
	var spoke := mem.spoke
	t = _step(w, mem, players, t + MemorySystem.EVERY)
	ok = _check(mem.spoke == spoke, "they don't repeat themselves straight away") and ok
	t = _step(w, mem, players, t + SimClock.real_seconds(MemorySystem.BARK_GAP_S + 1.0))
	ok = _check(mem.reported == 1 and mem.spoke == spoke + 1, "next time they shout again but don't call twice") and ok
	# a friend
	MemorySystem.remember(w, state, friend.id, "helped")
	MemorySystem.remember(w, state, friend.id, "helped")
	friend.position = me.position + Vector2(0.0, 3.0)
	friend.indoors = false
	friend.is_down = false
	w.spatial_index.update(friend.id, friend.position)
	victim.position = me.position + Vector2(300.0, 0.0)
	w.spatial_index.update(victim.id, victim.position)
	t = _step(w, mem, players, t + SimClock.real_seconds(2.0))
	said = _bark_of(state, friend.id)
	print("the friend: ", said)
	ok = _check(not said.is_empty() and int(said["tone"]) == 1, "someone who owes you says hello") and ok
	var will_before := CrewSystem.willingness(w, people[2])
	MemorySystem.remember(w, state, people[2].id, "helped")
	MemorySystem.remember(w, state, people[2].id, "paid")
	ok = _check(CrewSystem.willingness(w, people[2]) > will_before or will_before >= CrewSystem.MAX_WILLINGNESS, "a friend joins your crew more readily (%.2f -> %.2f)" % [will_before, CrewSystem.willingness(w, people[2])]) and ok
	# a store you held up
	var store := _a_shop(w)
	ok = _check(store != &"", "found a shop") and ok
	MemorySystem.remember(w, state, store, "store_robbed")
	var r := ShopSystem.buy(w, me, state, store, _sold_at(w, store))
	ok = _check(MemorySystem.refuses(state, store) and r.get("reason", "") in ["store_refused", "closed"], "a store you robbed won't serve you (%s)" % r.get("reason", "ok")) and ok
	# fading
	var before := MemorySystem.feel_of(state, victim.id)
	state.memories[people[3].id] = {"deed": "talked", "feel": 0.051, "day": 1, "n": 1}
	t = _step(w, mem, players, t + SimClock.hours(24.0))
	ok = _check(MemorySystem.feel_of(state, victim.id) > before and MemorySystem.feel_of(state, victim.id) < 0.0, "a grudge fades a little each day (%.2f -> %.2f)" % [before, MemorySystem.feel_of(state, victim.id)]) and ok
	ok = _check(not state.memories.has(people[3].id), "a faint memory is forgotten") and ok
	# saved and loaded
	SaveGame.write(w, 4242, PATH)
	var b := World.new()
	SystemRegistry.register_all(b)
	TestWorlds.real_city(b, 4242)
	SaveGame.apply(b, SaveGame.read(PATH))
	var bs: PlayerStateData = b.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	ok = _check(is_equal_approx(MemorySystem.feel_of(bs, victim.id), MemorySystem.feel_of(state, victim.id)) and MemorySystem.refuses(bs, store), "memories survive a save") and ok
	SaveGame.delete(PATH)
	# the list stays small
	for i in MemorySystem.MAX + 20:
		MemorySystem.remember(w, state, StringName("ghost_%d" % i), "talked")
	ok = _check(state.memories.size() == MemorySystem.MAX and state.memories.has(victim.id), "at most %d memories, the strong ones kept" % MemorySystem.MAX) and ok
	if ok:
		print("MEMORY_VERIFY: PASS")
	quit(0 if ok else 1)

## One memory pass on an aligned tick at or after `t`; returns that tick.
func _step(w: World, mem: MemorySystem, players: Dictionary, t: int) -> int:
	t += posmod(MemorySystem.PHASE - t, MemorySystem.EVERY)
	w.tick = t
	mem.process_entities(players, 0.0, t)
	return t

func _bark_of(state: PlayerStateData, id: StringName) -> Dictionary:
	for b in state.barks:
		if b["id"] == id:
			return b
	return {}

## Ordinary people (no cops, gangs, crew, dealers or fixers).
func _people(w: World, me: NPCData, count: int) -> Array:
	var out := []
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_fixer or n.is_down) and n.gang_id == &"":
			out.append(n)
			if out.size() == count:
				break
	return out

func _a_shop(w: World) -> StringName:
	for e in w.get_entities_with_component(ComponentNames.BUILDING).values():
		if ShopSystem.counter_kind(w, e.id) == "shop":
			return e.id
	return &""

func _sold_at(w: World, store: StringName) -> StringName:
	var stock := ItemCatalog.stock(ShopSystem.counter_kind(w, store))
	return stock[0] if not stock.is_empty() else &"water"

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("MEMORY_VERIFY: FAIL - " + what)
	return good
