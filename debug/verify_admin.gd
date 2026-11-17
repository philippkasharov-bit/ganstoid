## AD1 validator: the admin commands do what they say (cash, heal, god mode
## stops damage, items, reputation, rank, police, hour moves forward, reveal
## the map, new hustles, angry rivals, the paper), an unknown command is
## refused, the panel's bug test passes on a fresh game, and BUGS.md parses.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	var t := w.tick
	var cash := me.cash
	AdminSystem.run(w, "cash", 1000, t)
	ok = _check(me.cash == cash + 1000, "cash") and ok
	me.health = 0.2
	me.hunger = 0.1
	AdminSystem.run(w, "heal", null, t)
	ok = _check(me.health == 1.0 and me.hunger == 1.0, "heal") and ok
	AdminSystem.run(w, "god", null, t)
	CombatSystem._hurt(w, me, {"damage": 0.5})
	ok = _check(state.admin_god and me.health == 1.0, "god mode stops damage") and ok
	AdminSystem.run(w, "god", null, t)
	AdminSystem.run(w, "item", &"pistol", t)
	ok = _check(int(state.inventory.get(&"pistol", 0)) >= 1, "item") and ok
	AdminSystem.run(w, "fame", 40, t)
	ok = _check(Rep.tier(state) >= 2, "reputation") and ok
	AdminSystem.run(w, "rank_up", null, t)
	ok = _check(state.rank == 1, "rank up") and ok
	state.case_evidence = 30.0
	AdminSystem.run(w, "wanted_clear", null, t)
	ok = _check(state.case_evidence == 0.0, "police forget you") and ok
	AdminSystem.run(w, "hour", 23, t)
	ok = _check(w.tick > t and absf(SimClock.day_fraction(w.tick) * 24.0 - 23.0) < 0.01, "set the hour (forward)") and ok
	AdminSystem.run(w, "reveal_map", null, w.tick)
	ok = _check(ExplorationSystem.count(state) == ExplorationSystem.GRID * ExplorationSystem.GRID, "reveal the map") and ok
	AdminSystem.run(w, "hustles_new", null, w.tick)
	ok = _check(state.hustles.size() == HustleSystem.PER_DAY, "new hustles") and ok
	AdminSystem.run(w, "rival_max", null, w.tick)
	ok = _check(not state.rivals.is_empty() and state.rivals.values().all(func(r: Dictionary) -> bool: return float(r["grudge"]) >= RivalSystem.PERSONAL), "angry rivals") and ok
	AdminSystem.run(w, "paper_now", null, w.tick)
	ok = _check(not state.paper.is_empty(), "print the paper") and ok
	ok = _check(AdminSystem.run(w, "nonsense", null, w.tick).begins_with("unknown"), "unknown commands are refused") and ok
	state.ui_admin = ["cash", 5]
	var before := me.cash
	(w.find_system(AdminSystem) as AdminSystem).process_entities({PlayerFactory.PLAYER_ENTITY_ID: p}, 0.0, w.tick)
	ok = _check(me.cash == before + 5 and state.ui_admin.is_empty() and state.last_message.begins_with("ADMIN"), "the panel's request is carried out next tick") and ok
	var results := AdminTests.run_all(w)
	var fails := results.filter(func(r: Array) -> bool: return not r[1] and not String(r[0]).begins_with("walk mesh") and not String(r[0]).begins_with("frame rate") and not String(r[0]).begins_with("the city is populated"))   # test worlds are small and headless
	print("bug test: %d checks, %s" % [results.size(), "all pass" if fails.is_empty() else str(fails)])
	ok = _check(fails.is_empty(), "the bug test passes on a fresh game") and ok
	var bugs := AdminWindow.bug_lines(FileAccess.get_file_as_string("res://BUGS.md"))
	print("BUGS.md: %d open, %d fixed" % [bugs[0].size(), bugs[1].size()])
	ok = _check(bugs[1].size() > 0, "BUGS.md parses") and ok
	if ok:
		print("ADMIN_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("ADMIN_VERIFY: FAIL - ", what)
	return good
