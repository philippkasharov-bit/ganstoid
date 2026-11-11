## RK1 validator: score -> rank thresholds, a rank once earned is kept, and a
## street rat cannot buy a gun from a dealer.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var rs := RankSystem.new(world)
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	var state := PlayerStateData.new()
	var p := Entity.new(me.id)
	p.add_component(me)
	p.add_component(state)
	world.register_entity(p)
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	var d := Entity.new(&"d")
	var dn := NPCData.new()
	dn.id = &"d"
	dn.is_dealer = true
	d.add_component(dn)
	world.register_entity(d)
	me.cash = 1000
	var refused := ShopSystem.buy(world, me, state, &"d", &"pistol")
	me.cash = 5000   # 100 points: Soldier
	world.tick = SimClock.hours(1.0)
	rs.process_entities(players, 0.0, world.tick)
	var earned := state.rank
	me.cash = 0
	world.tick = SimClock.hours(2.0)
	rs.process_entities(players, 0.0, world.tick)
	print("street rat buying a gun: %s; $5000 -> %s; broke an hour later: %s" % [refused.get("reason"), RankSystem.name_of(earned), RankSystem.name_of(state.rank)])
	if refused.get("reason") == "nobody_gun" and earned == 2 and state.rank == 2:
		print("RANKS_VERIFY: PASS")
		quit()
	else:
		print("RANKS_VERIFY: FAIL - ranks and the gun gate")
		quit(1)
