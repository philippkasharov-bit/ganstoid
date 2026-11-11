## Combat C1-C5 validator, on a hand-built world (no city): rules, not tuning.
##   1. Fists: a person in front within reach is hit; one behind is not.
##   2. Pistol: aimed shots down a line hit the first body; rounds are counted;
##      an empty gun refuses; enough hits put someone down for good.
##   3. A downed person drops out of the routine (the street sim leaves them).
##   4. A gunshot sends nearby people on the street running home; far ones carry on.
extends SceneTree

func _initialize() -> void:
	var ok := _fists() and _pistol() and _gunshot_panic() and _gang_fights_back() and _cops_shoot_only_armed()
	if ok:
		print("COMBAT_VERIFY: PASS")
	quit(0 if ok else 1)

func _world_with(people: Array) -> Array:
	var world := World.new()
	var player := Entity.new(PlayerFactory.PLAYER_ENTITY_ID)
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	me.position = Vector2(100, 100)
	var state := PlayerStateData.new()
	player.add_component(me)
	player.add_component(state)
	world.register_entity(player)
	world.reindex_position(me.id)
	for p in people:
		var e := Entity.new(StringName(p[0]))
		var n := NPCData.new()
		n.id = StringName(p[0])
		n.position = p[1]
		e.add_component(n)
		world.register_entity(e)
		world.reindex_position(n.id)
	return [world, me, state]

func _npc(world: World, id: String) -> NPCData:
	return world.entities[StringName(id)].get_component(ComponentNames.NPC)

func _fists() -> bool:
	var w := _world_with([["front", Vector2(101, 100)], ["behind", Vector2(99, 100)]])
	var state: PlayerStateData = w[2]
	state.aim_point = Vector2(110, 100)
	var rng := RandomNumberGenerator.new()
	var r := CombatSystem.attack(w[0], w[1], state, 0, rng)
	var again := CombatSystem.attack(w[0], w[1], state, 1, rng)   # still swinging: refused
	print("fists: hit %s, front health %.2f, behind health %.2f, second swing at once: %s" % [r.get("hit_id"), _npc(w[0], "front").health, _npc(w[0], "behind").health, again.get("reason")])
	return _check(r.get("hit_id") == &"front" and _npc(w[0], "behind").health == 1.0 and again.get("reason") == "not_ready", "fists hit who is in front, not behind, at a human pace")

func _pistol() -> bool:
	var w := _world_with([["near", Vector2(110, 100)], ["far", Vector2(120, 100)], ["side", Vector2(110, 108)]])
	var state: PlayerStateData = w[2]
	state.weapon = &"pistol"
	state.aiming = true
	state.ammo = 3
	state.aim_point = Vector2(130, 100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var tick := 0
	var hit_ids: Array = []
	for i in 3:
		var r := CombatSystem.attack(w[0], w[1], state, tick, rng)
		hit_ids.append(r.get("hit_id", &""))
		tick += 60
	var empty := CombatSystem.attack(w[0], w[1], state, tick, rng)
	var near := _npc(w[0], "near")
	print("pistol: aimed shots hit %s, far %.2f, side %.2f, near down %s, ammo %d, empty gun: %s" % [hit_ids, _npc(w[0], "far").health, _npc(w[0], "side").health, near.is_down, state.ammo, empty.get("reason")])
	# the first body on the line takes the rounds until it is down; then the next one does
	if not _check(hit_ids == [&"near", &"near", &"far"] and _npc(w[0], "side").health == 1.0, "aimed rounds stop in the first standing body on the line"):
		return false
	if not _check(near.is_down and state.ammo == 0 and empty.get("reason") == "no_ammo", "two hits down a person; rounds run out"):
		return false
	var street := NPCStreet.new(w[0])
	street.start_trip(near, [], Vector2(200, 100), 0.0)
	street.step_all(1.0 / 60.0, 1, Vector2.INF)
	return _check(near.position == Vector2(110, 100) and street.outside.is_empty(), "the downed stay where they fell, out of the street sim")

func _gunshot_panic() -> bool:
	var w := _world_with([["close", Vector2(150, 100)], ["far", Vector2(900, 100)]])
	var world: World = w[0]
	for b in [["home_c", Vector2(160, 140)], ["home_f", Vector2(910, 140)]]:
		var e := Entity.new(StringName(b[0]))
		var bd := BuildingData.new()
		bd.position = b[1]
		e.add_component(bd)
		world.register_entity(e)
	_npc(world, "close").home_building_id = &"home_c"
	_npc(world, "far").home_building_id = &"home_f"
	var schedule := NPCScheduleSystem.new(world)
	for id in ["close", "far"]:
		schedule.street.start_trip(_npc(world, id), [], Vector2(500, 500), 0.0)
	schedule.on_gunshot(GanstoidEvents.GUNSHOT, {"position": Vector2(100, 100), "heard_m": 300.0, "tick": 0})
	print("gunshot: fled %d, close now heading to %s at %.1f m/s, far heading to %s" % [schedule.fled, schedule.street.final_of(&"close"), schedule.street.pace_now.get(&"close", 0.0), schedule.street.final_of(&"far")])
	return _check(schedule.fled == 1 and schedule.street.final_of(&"close") == Vector2(160, 140) and schedule.street.final_of(&"far") == Vector2(500, 500), "people in earshot run home, the rest carry on")

## C6: hurt a gang member and the gang nearby turns on you and fires; the player
## can be hurt and put down for good.
func _gang_fights_back() -> bool:
	var w := _world_with([["victim", Vector2(101, 100)], ["brother", Vector2(106, 106)], ["stranger", Vector2(96, 108)], ["far_brother", Vector2(400, 100)]])
	var world: World = w[0]
	var me: NPCData = w[1]
	for id in ["victim", "brother", "far_brother"]:
		_npc(world, id).gang_id = &"g1"
	var combat := NPCCombatSystem.new(world)
	world.event_bus.subscribe(combat.on_assaulted)
	var state: PlayerStateData = w[2]
	state.aim_point = Vector2(105, 100)
	CombatSystem.attack(world, me, state, 0, RandomNumberGenerator.new())
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	for t in range(1, 60 * 30):
		combat.process_entities(players, 1.0 / 60.0, t)
		if me.is_down and combat.hostile.is_empty():
			break
	print("gang: hostile %s, shots %d, player health %.2f, down %s" % [combat.hostile.keys(), combat.shots_fired, me.health, me.is_down])
	return _check(combat.hostile.is_empty() and combat.shots_fired >= 2 and me.is_down and not _npc(world, "stranger").is_busy, "the near gang fires until the player is down, then stands down; others stay out")

## C6: an alerted cop shoots only at an armed threat in sight.
func _cops_shoot_only_armed() -> bool:
	var w := _world_with([["cop", Vector2(110, 100)]])
	var world: World = w[0]
	var state: PlayerStateData = w[2]
	var combat := NPCCombatSystem.new(world)
	var cop := _npc(world, "cop")
	var unarmed := combat.cop_engages(cop, w[1], state, 100)
	state.weapon = &"pistol"
	state.aiming = true
	var armed := not combat.cop_engages(cop, w[1], state, 100)
	print("cop: engages unarmed %s, still closing in at 10 m %s, shots %d" % [unarmed, armed, combat.shots_fired])
	return _check(not unarmed and combat.shots_fired == 1, "cops fire only at a raised gun (and keep closing from 10 m)")

func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("COMBAT_VERIFY: FAIL - ", what)
	return ok
