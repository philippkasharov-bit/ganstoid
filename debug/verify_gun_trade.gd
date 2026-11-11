## WP1 validator: selling guns to a gang pays, raises standing (clean guns
## more), arms the gang; never touches heat.
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
	var g := Entity.new(&"g1")
	var gang := GangData.new()
	gang.id = &"g1"
	g.add_component(gang)
	world.register_entity(g)
	var buyer := NPCData.new()
	buyer.id = &"b"
	buyer.gang_id = &"g1"
	buyer.position = Vector2(1, 0)
	state.inventory[&"pistol"] = 1
	state.inventory[&"pistol_clean"] = 1
	var a := GunTrade.sell(world, me, state, buyer)
	var after_clean: float = state.gang_standing[&"g1"]
	var b := GunTrade.sell(world, me, state, buyer)
	var c := GunTrade.sell(world, me, state, buyer)
	print("sold %s $%d then %s $%d, then %s; standing %.2f -> %.2f; armory %d, edge x%.2f; cash %d; heat %d" % [a.get("effect"), a.get("amount"), b.get("effect"), b.get("amount"), c.get("reason"), after_clean, state.gang_standing[&"g1"], gang.armory, GunTrade.armed_edge(world, &"g1"), me.cash, state.law_tier])
	if a.get("amount") == 1300 and b.get("amount") == 600 and c.get("reason") == "no_gun_to_sell" and after_clean > 0.6 and state.gang_standing[&"g1"] > after_clean and gang.armory == 3 and me.cash == 1900 and state.law_tier == 0:
		print("GUN_TRADE_VERIFY: PASS")
		quit()
	else:
		print("GUN_TRADE_VERIFY: FAIL - gun trade")
		quit(1)
