## D1/BR1 validator: small talk builds trust and, once warm, gives a tip;
## threatening or paying a witness wipes their memory and cancels their call;
## a cop on the take cuts the case, an honest one adds to it.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var calls := WitnessCallSystem.new(world)
	world.register_system(calls)
	var me := _npc(world, PlayerFactory.PLAYER_ENTITY_ID, Vector2.ZERO)
	var state := PlayerStateData.new()
	world.entities[me.id].add_component(state)
	world.reindex_components(me.id)
	me.cash = 5000
	var w := _npc(world, &"w", Vector2(2, 0))
	var fixer := _npc(world, &"f", Vector2(60, 0))
	fixer.is_fixer = true
	var a := TalkSystem.small_talk(world, me, w)
	TalkSystem.small_talk(world, me, w)
	var b := TalkSystem.small_talk(world, me, w)
	w.recognition_chance = 0.9
	calls.queue(w, {"position": Vector2.ZERO, "severity": 0.5})
	TalkSystem.pay_off(world, me, w)
	print("talk: %s -> %s (%s); paid off: memory %.1f, pending calls %d" % [a.get("effect"), b.get("effect"), b.get("tip", ""), w.recognition_chance, calls.pending()])
	if not _check(a.get("effect") == "talk_cold" and b.get("effect") == "talk_tip" and w.recognition_chance == 0.0 and calls.pending() == 0, "talk earns tips; paying a witness silences them"):
		return
	var on_take := StringName()
	var honest := StringName()
	for i in 200:
		var id := StringName("cop%d" % i)
		if NPCRoutine.unit(id, 31) < 0.3 and on_take == &"":
			on_take = id
		if NPCRoutine.unit(id, 31) > 0.9 and honest == &"":
			honest = id
	var c1 := _npc(world, on_take, Vector2(3, 0))
	var c2 := _npc(world, honest, Vector2(3, 0))
	c1.is_cop = true
	c2.is_cop = true
	state.case_evidence = 50.0
	var r1 := TalkSystem.bribe_cop(world, me, state, c1)
	var after := state.case_evidence
	var r2 := TalkSystem.bribe_cop(world, me, state, c2)
	print("bribe: %s -> case %.0f; honest cop: %s -> case %.0f" % [r1.get("effect"), after, r2.get("reason"), state.case_evidence])
	if not _check(r1.get("effect") == "bribed" and after == 10.0 and r2.get("reason") == "bribe_refused" and state.case_evidence == 30.0, "bent cops cut the case, honest ones add to it"):
		return
	print("TALK_VERIFY: PASS")
	quit()

func _npc(world: World, id: StringName, at: Vector2) -> NPCData:
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
		print("TALK_VERIFY: FAIL - ", what)
		quit(1)
	return good
