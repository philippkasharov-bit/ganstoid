## G2 validator: needs drain at the planned daily rates, low needs slow you
## and shake your aim, food and water put them back, thirst at zero kills,
## sleep in your own bed rests in about eight hours and you wake when hurt.
extends SceneTree

func _initialize() -> void:
	var w := _world()
	var world: World = w[0]
	var me: NPCData = w[1]
	var state: PlayerStateData = w[2]
	var needs := NeedsSystem.new()
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	var day := SimClock.day_ticks
	for t in day / 2:   # half a game day awake
		needs.process_entities(players, 1.0 / SimClock.TICKS_PER_SECOND, t)
	print("after 12 game hours: food %.2f water %.2f rest %.2f" % [me.hunger, me.thirst, me.fatigue])
	if not _check(absf(me.hunger - 0.7) < 0.02 and absf(me.thirst - 0.5) < 0.02 and absf(me.fatigue - 0.25) < 0.02, "needs drain at the daily rates"):
		return
	me.hunger = 0.1
	print("hungry: speed x%.2f, spread x%.2f" % [NeedsSystem.speed_factor(me), NeedsSystem.spread_factor(me)])
	if not _check(NeedsSystem.speed_factor(me) < 1.0 and NeedsSystem.spread_factor(me) > 1.0, "a low need slows you and shakes your aim"):
		return
	state.inventory[&"burrito"] = 1
	var ate := NeedsSystem.use_item(me, state, &"burrito")
	var again := NeedsSystem.use_item(me, state, &"burrito")
	if not _check(ate["ok"] and absf(me.hunger - 0.6) < 0.01 and again["reason"] == "dont_have", "eating restores hunger and uses the item up"):
		return
	# sleep at home from rest 0.25: about 6 game hours to full, then wake
	var slept := NeedsSystem.toggle_sleep(world, me, state)
	var ticks := 0
	while state.sleeping and ticks < day:
		needs.process_entities(players, 1.0 / SimClock.TICKS_PER_SECOND, ticks)
		ticks += 1
	var hours := ticks * 24.0 / day
	print("sleep: %s, woke after %.1f game hours, rest %.2f" % [slept.get("effect"), hours, me.fatigue])
	if not _check(slept.get("effect") == "sleep_home" and hours > 5.0 and hours < 7.0, "your own bed rests you in hours, then you wake"):
		return
	me.fatigue = 0.3
	NeedsSystem.toggle_sleep(world, me, state)
	me.health -= 0.2   # someone hits you in your sleep
	needs.process_entities(players, 1.0 / SimClock.TICKS_PER_SECOND, 0)
	if not _check(not state.sleeping, "getting hurt wakes you"):
		return
	me.thirst = 0.0
	me.health = 1.0
	var t := 0
	while not me.is_down and t < day * 2:
		needs.process_entities(players, 1.0 / SimClock.TICKS_PER_SECOND, t)
		t += 1
	print("no water: down after %.1f game hours" % (t * 24.0 / day))
	if not _check(me.is_down and t < day * 1.2, "going without water kills within about a day"):
		return
	print("NEEDS_VERIFY: PASS")
	quit()

func _world() -> Array:
	var world := World.new()
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	me.home_building_id = &"home"
	var state := PlayerStateData.new()
	var p := Entity.new(me.id)
	p.add_component(me)
	p.add_component(state)
	world.register_entity(p)
	var h := Entity.new(&"home")
	var b := BuildingData.new()
	b.id = &"home"
	h.add_component(b)
	world.register_entity(h)
	return [world, me, state]

func _check(good: bool, what: String) -> bool:
	if not good:
		print("NEEDS_VERIFY: FAIL - ", what)
		quit(1)
	return good
