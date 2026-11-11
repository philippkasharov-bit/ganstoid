## G3 validator: a knife wound bleeds and kills if untreated, a bandage stops
## it, a beating knocks someone out and they get up later and go on with
## their day; a bystander's wound closes by itself.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var me := _person(world, PlayerFactory.PLAYER_ENTITY_ID, Vector2(100, 100))
	var state := PlayerStateData.new()
	world.entities[me.id].add_component(state)
	world.reindex_components(me.id)
	var victim := _person(world, &"v", Vector2(101, 100))
	var target := _person(world, &"t", Vector2(130, 100))
	var wounds := WoundSystem.new(world)
	world.event_bus.subscribe(wounds.on_wounded)
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	# a knife cut on the player: bleeds until bandaged
	world.event_bus.emit(GanstoidEvents.WOUNDED, {"id": me.id})
	me.bleeding = true
	for t in 60 * 30:
		world.tick = t
		wounds.process_entities(players, 1.0 / 60.0, t)
	var after_30s := me.health
	state.inventory[&"bandage"] = 1
	NeedsSystem.use_item(me, state, &"bandage")
	print("player bleeding 30 s: health %.2f; bandaged: bleeding %s" % [after_30s, me.bleeding])
	if not _check(absf(after_30s - 0.8) < 0.01 and not me.bleeding, "a wound bleeds 0.4 a minute and a bandage stops it"):
		return
	# fists knock out, never kill
	victim.health = 0.15
	state.aim_point = victim.position
	var r := CombatSystem.attack(world, me, state, world.tick, RandomNumberGenerator.new())
	var out_at := world.tick
	print("punch on a hurt man: %s, down %s, bleeding %s" % [r.keys(), victim.is_down, victim.bleeding])
	if not _check(r.get("knocked_out", false) and victim.is_down and not victim.bleeding, "a beating knocks out without a wound"):
		return
	var t := out_at
	while victim.is_down and t < out_at + 60 * 200:
		t += 1
		world.tick = t
		wounds.process_entities(players, 1.0 / 60.0, t)
	print("knocked out for %.0f s, wakes with health %.2f" % [(t - out_at) / 60.0, victim.health])
	if not _check(not victim.is_down and absf((t - out_at) / 60.0 - CombatSystem.KO_S) < 1.0 and victim.health >= 0.3, "a knockout ends and they get up"):
		return
	# a passer-by's bullet wound: bleeds a while, then closes
	target.health = 0.9
	target.bleeding = true
	world.event_bus.emit(GanstoidEvents.WOUNDED, {"id": &"t"})
	var start := world.tick
	for k in 60 * 120:
		world.tick = start + k
		wounds.process_entities(players, 1.0 / 60.0, world.tick)
	print("bystander after 2 min: bleeding %s, health %.2f, down %s" % [target.bleeding, target.health, target.is_down])
	if not _check(not target.bleeding and not target.is_down, "a bystander's wound closes by itself"):
		return
	print("WOUNDS_VERIFY: PASS")
	quit()

func _person(world: World, id: StringName, at: Vector2) -> NPCData:
	var e := Entity.new(id)
	var n := NPCData.new()
	n.id = id
	n.position = at
	e.add_component(n)
	world.register_entity(e)
	world.reindex_position(id)
	return n

func _check(good: bool, what: String) -> bool:
	if not good:
		print("WOUNDS_VERIFY: FAIL - ", what)
		quit(1)
	return good
