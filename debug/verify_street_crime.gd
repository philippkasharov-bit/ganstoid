## X2 validator: mugging needs a raised weapon and takes what they carry;
## burglary takes the break-in time, pays, cannot be repeated on the same
## house for days, and someone home reports it.
extends SceneTree

var _reports := 0

func _initialize() -> void:
	var world := World.new()
	world.register_system(WitnessCallSystem.new(world))
	world.event_bus.subscribe(func(n: StringName, _p: Dictionary) -> void:
		if n == GanstoidEvents.CRIME_WITNESSED:
			_reports += 1)
	var me := _person(world, PlayerFactory.PLAYER_ENTITY_ID, Vector2(100, 100))
	var state := PlayerStateData.new()
	world.entities[me.id].add_component(state)
	world.reindex_components(me.id)
	var mark := _person(world, &"mark", Vector2(102, 100))
	mark.cash = 60
	var unarmed := StreetCrime.mug(world, me, state, mark)
	state.weapon = &"pistol"
	state.aiming = true
	var armed := StreetCrime.mug(world, me, state, mark)
	print("mug: unarmed %s, pistol up %s %s, their cash %d, your cash %d" % [unarmed.get("reason"), armed.get("effect"), armed.get("amount"), mark.cash, me.cash])
	if not _check(unarmed.get("reason") == "need_weapon_up" and armed.get("amount") == 60 and mark.cash == 0 and me.cash == 60, "a raised weapon gets the wallet"):
		return
	var h := Entity.new(&"house")
	var house := BuildingData.new()
	house.id = &"house"
	house.building_type = GanstoidEnums.BuildingType.RESIDENCE
	house.position = Vector2(100, 101)
	h.add_component(house)
	world.register_entity(h)
	var owner := _person(world, &"owner", house.position)
	owner.home_building_id = &"house"
	owner.indoors = true
	world.tick = SimClock.hours(2.0)
	var start := StreetCrime.start_burglary(world, me, state, &"house")
	var got := {}
	var t := 0
	while got.is_empty() and t < 60 * 20:
		world.tick += 1
		t += 1
		got = StreetCrime.advance_burglary(world, me, state)
	(world.find_system(WitnessCallSystem) as WitnessCallSystem).flush()
	var again := StreetCrime.start_burglary(world, me, state, &"house")
	print("burglary: %s, done after %.1f s: %s $%s + %s; owner home reported: %s; again at once: %s" % [start.get("effect"), t / 60.0, got.get("effect"), got.get("amount"), got.get("item"), _reports > 0, again.get("reason")])
	if not _check(got.get("effect") == "burgled" and absf(t / 60.0 - StreetCrime.WAYS_IN["pick"][0]) < 0.1 and _reports > 0 and again.get("reason") == "already_cleaned_out", "a break-in takes its time, pays, gets reported by whoever is home, and the house is empty after"):
		return
	print("STREET_CRIME_VERIFY: PASS")
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
		print("STREET_CRIME_VERIFY: FAIL - ", what)
		quit(1)
	return good
