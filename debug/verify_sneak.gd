## B3: crouched (C) you are seen from half as far: a witness at 0.75 of the
## sight range sees you standing, not sneaking; only you are hidden by it.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	me.position = Vector2(100, 100)
	var st := PlayerStateData.new()
	var e := Entity.new(me.id)
	e.add_component(me)
	e.add_component(st)
	world.register_entity(e)
	world.tick = SimClock.hours(12.0)
	var eye := me.position + Vector2(CrimeSystem.SIGHT_DAY_M * 0.75, 0)
	var ok := CrimeSystem.can_see(world, eye, me.position)
	st.sneaking = true
	ok = ok and not CrimeSystem.can_see(world, eye, me.position)
	ok = ok and CrimeSystem.can_see(world, eye, me.position + Vector2(10, 0)) == CrimeSystem.can_see(world, eye, me.position + Vector2(10, 0))
	ok = ok and CrimeSystem.can_see(world, me.position + Vector2(CrimeSystem.SIGHT_DAY_M * 0.4, 0), me.position)   # close up they still see you
	print("SNEAK_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
