## I1/CP1 validator: witness reports build a case, it cools by the hour
## (faster at home), a warrant makes a cop who sees you come, a lawyer
## thins it, court sends a strong case to prison (dirty money, drugs, guns
## taken), and you walk out at home with a clean slate.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 8)
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var state: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var case := world.find_system(CaseSystem) as CaseSystem
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {"position": me.position, "severity": 1.0, "tick": world.tick})
	world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {"position": me.position, "severity": 1.0, "tick": world.tick})
	var built := state.case_evidence
	me.position += Vector2(200, 0)
	world.tick = SimClock.hours(30.0)
	case.process_entities(players, 0.0, world.tick)
	var cooled := state.case_evidence
	Wallet.earn_clean(world, 600)
	var law := CaseSystem.lawyer(world, me, state)
	print("case %.0f, an hour later %.0f, after a lawyer %.0f (%s)" % [built, cooled, state.case_evidence, law.get("effect")])
	if not _check(built == 40.0 and cooled == 38.5 and state.case_evidence == 8.5, "reports build, time cools, a lawyer thins"):
		return
	state.case_evidence = 90.0
	Wallet.earn_dirty(world, 300)
	state.inventory[&"pistol"] = 1
	state.inventory[&"weed"] = 4
	state.inventory[&"water"] = 2
	var days := CaseSystem.sentence(world, me, state)
	print("court on a case of 90: %d days; dirty %d, pistol %d, weed %d, water kept %d" % [days, state.dirty_cash, state.inventory.get(&"pistol", 0), state.inventory.get(&"weed", 0), state.inventory.get(&"water", 0)])
	if not _check(days == 5 and state.dirty_cash == 0 and not state.inventory.has(&"pistol") and not state.inventory.has(&"weed") and state.inventory.get(&"water") == 2, "court takes the dirty, the drugs and the guns"):
		return
	world.tick = state.prison_until_tick
	case.process_entities(players, 0.0, world.tick)
	var home: Vector2 = world.entities[me.home_building_id].get_component(ComponentNames.BUILDING).position
	print("released: free %s, at home %s, case %.0f" % [state.prison_until_tick == 0, me.position == home, state.case_evidence])
	if not _check(state.prison_until_tick == 0 and me.position == home and state.case_evidence == 0.0, "time served: home, clean slate"):
		return
	print("CASE_VERIFY: PASS")
	quit()

func _check(good: bool, what: String) -> bool:
	if not good:
		print("CASE_VERIFY: FAIL - ", what)
		quit(1)
	return good
