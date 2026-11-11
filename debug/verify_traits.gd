## T1/F1 validator: deeds earn a trait at its count and gold later, with both
## edges applied; fame rises when people see a crime, unseen crimes count to
## Ghost, and Ghost halves how readily a face is placed.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	var state := PlayerStateData.new()
	var p := Entity.new(me.id)
	p.add_component(me)
	p.add_component(state)
	world.register_entity(p)
	for i in 4:
		Traits.deed(world, state, &"cars")
	var before := Traits.has(state, &"wheelman")
	Traits.deed(world, state, &"cars")
	var normal := Traits.edge(state, &"wheelman", 1.4)
	for i in 15:
		Traits.deed(world, state, &"cars")
	var gold := Traits.edge(state, &"wheelman", 1.4)
	print("wheelman at 4: %s, at 5: x%.2f, at 20 (gold): x%.2f; message: %s" % [before, normal, gold, state.last_message])
	if not _check(not before and is_equal_approx(normal, 1.4) and is_equal_approx(gold, 1.6), "a trait comes at its count and goes gold later"):
		return
	CrimeSystem.broadcast_witnesses(world, Vector2(5000, 5000), 0.5)   # nobody near
	var w := NPCData.new()
	w.id = &"w"
	w.position = Vector2(3, 0)
	var e := Entity.new(&"w")
	e.add_component(w)
	world.register_entity(e)
	world.reindex_position(&"w")
	world.tick = SimClock.hours(12.0)
	CrimeSystem.broadcast_witnesses(world, Vector2.ZERO, 0.5)
	print("unseen deeds %d, fame after a seen crime %.1f, face factor plain %.2f" % [state.deeds.get(&"unseen", 0), state.fame, CrimeSystem._face_factor(state)])
	state.traits[&"ghost"] = 1
	print("with Ghost: face factor %.2f" % CrimeSystem._face_factor(state))
	if not _check(state.deeds.get(&"unseen", 0) == 1 and state.fame == 2.5 and is_equal_approx(CrimeSystem._face_factor(state), 1.025 / 2.0), "fame from being seen, Ghost from not"):
		return
	print("TRAITS_VERIFY: PASS")
	quit()

func _check(good: bool, what: String) -> bool:
	if not good:
		print("TRAITS_VERIFY: FAIL - ", what)
		quit(1)
	return good
