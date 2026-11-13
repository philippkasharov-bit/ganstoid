## W1 validator: a witness needs to see it. 12 m away counts by day, not at
## night; nobody beyond 15 m; a recognition roll is never made for someone
## who could not see (their memory of you does not move). R3D10b: at night
## under a street lamp you are seen from 12 m again; in a dark gap only close.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	world.tick = SimClock.hours(13.0)
	var day12 := CrimeSystem.can_see(world, Vector2.ZERO, Vector2(12, 0))
	var day20 := CrimeSystem.can_see(world, Vector2.ZERO, Vector2(20, 0))
	world.tick = SimClock.hours(23.0)
	var night12 := CrimeSystem.can_see(world, Vector2.ZERO, Vector2(12, 0))
	var night6 := CrimeSystem.can_see(world, Vector2.ZERO, Vector2(6, 0))
	StreetLights.active = StreetLights.new()
	StreetLights.active.add(Vector3(12, 0, StreetLights.LAMP_R))
	var lamp12 := CrimeSystem.can_see(world, Vector2.ZERO, Vector2(12, 0))
	var dark_beside := CrimeSystem.can_see(world, Vector2(30, 0), Vector2(30, 7))   # a dark gap: 7 m is too far
	StreetLights.active = null
	var far := NPCData.new()
	far.id = &"far"
	far.position = Vector2(40, 0)
	var e := Entity.new(&"far")
	e.add_component(far)
	world.register_entity(e)
	world.reindex_position(&"far")
	CrimeSystem.broadcast_witnesses(world, Vector2.ZERO, 0.5)
	print("day 12 m %s, day 20 m %s, night 12 m %s, night 6 m %s, under a lamp 12 m %s, dark gap 7 m %s; 40 m away remembers %.2f" % [day12, day20, night12, night6, lamp12, dark_beside, far.recognition_chance])
	if day12 and not day20 and not night12 and night6 and lamp12 and not dark_beside and far.recognition_chance == 0.0:
		print("WITNESS_SIGHT_VERIFY: PASS")
		quit()
	else:
		print("WITNESS_SIGHT_VERIFY: FAIL - sight range by light")
		quit(1)
