## TR validator on the real city:
##   1. Each gang starts holding the cells round its fronts, with ten members.
##   2. Tags raise your hold and dent theirs; it fades by the hour.
##   3. Posted crew build influence until you hold a cell; the morning pays tax.
##   4. Muscling into a gang's cell brings a squad after you.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 3)
	var t := TerritorySystem.data(world)
	var held := {}
	var members := {}
	for g in world.get_entities_with_component(ComponentNames.GANG).values():
		var gang: GangData = g.get_component(ComponentNames.GANG)
		held[gang.id] = TerritorySystem.cells_held(t, gang.id)
		members[gang.id] = gang.member_npc_ids.size()
	print("cells held at start %s, members %s" % [held, members])
	if not _check(held.values().all(func(v: int) -> bool: return v >= 1) and members.values().all(func(v: int) -> bool: return v >= 10), "gangs start with turf and people"):
		return
	var turf := world.find_system(TerritorySystem) as TerritorySystem
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var state: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var gang0: GangData = world.entities[&"gang_0"].get_component(ComponentNames.GANG)
	var front: Vector2 = world.entities[gang0.territory_building_ids[0]].get_component(ComponentNames.BUILDING).position
	var c := TerritoryData.cell_of(front)
	var theirs := TerritorySystem.get_influence(t, c, &"gang_0")
	me.position = front
	world.reindex_position(me.id)
	for i in 4:
		TerritorySystem.tag(world, me)
	var mine := TerritorySystem.get_influence(t, c, TerritorySystem.PLAYER)
	print("4 tags on their front: you %.0f, them %.0f -> %.0f" % [mine, theirs, TerritorySystem.get_influence(t, c, &"gang_0")])
	if not _check(mine == 32.0 and TerritorySystem.get_influence(t, c, &"gang_0") < theirs, "tags build yours and dent theirs"):
		return
	# one game hour later they react
	var combat := world.find_system(NPCCombatSystem) as NPCCombatSystem
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	world.tick += SimClock.hours(1.0)
	turf.process_entities(players, 0.0, world.tick)
	print("an hour later: you %.0f, squad after you: %d" % [TerritorySystem.get_influence(t, c, TerritorySystem.PLAYER), combat.hostile.size()])
	if not _check(combat.hostile.size() == TerritorySystem.SQUAD_SIZE, "a gang sends people after you"):
		return
	# an empty cell held by posted crew, then tax at 06:00
	var quiet := Vector2i(-50, -50)
	TerritorySystem.set_influence(t, quiet, TerritorySystem.PLAYER, 60.0)
	var cash_before := me.cash
	world.tick = (world.tick / SimClock.day_ticks + 1) * SimClock.day_ticks + SimClock.hours(6.5)
	turf.process_entities(players, 0.0, world.tick)
	print("held %d, cash %d -> %d" % [TerritorySystem.cells_held(t, TerritorySystem.PLAYER), cash_before, me.cash])
	if not _check(TerritorySystem.cells_held(t, TerritorySystem.PLAYER) >= 1 and me.cash > cash_before, "held blocks pay street tax in the morning"):
		return
	print("TERRITORY_VERIFY: PASS")
	quit()

func _check(good: bool, what: String) -> bool:
	if not good:
		print("TERRITORY_VERIFY: FAIL - ", what)
		quit(1)
	return good
