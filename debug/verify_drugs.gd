## DR1 validator: a safehouse makes what it is set to, at that recipe's cost
## and yield; C collects then switches; collecting gives that drug.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	me.cash = 1000
	var state := PlayerStateData.new()
	var p := Entity.new(me.id)
	p.add_component(me)
	p.add_component(state)
	world.register_entity(p)
	var e := Entity.new(&"lab")
	var lab := BuildingData.new()
	lab.id = &"lab"
	lab.building_type = GanstoidEnums.BuildingType.SAFEHOUSE
	lab.owner_npc_id = PlayerFactory.PLAYER_ENTITY_ID
	e.add_component(lab)
	world.register_entity(e)
	ProductionSystem.grow_all(world)
	var weed := lab.stored_product
	var sw := ProductionSystem.switch_product(world, &"lab")
	sw = ProductionSystem.switch_product(world, &"lab")
	sw = ProductionSystem.switch_product(world, &"lab")   # weed -> pills -> meth -> coke
	ProductionSystem.grow_all(world)
	var coke := lab.stored_product
	ProductionSystem.collect(world, &"lab")
	print("weed day: %d, after switching to %s: %d made, cash %d, carrying weed %d coke %d" % [weed, lab.product, coke, me.cash, state.inventory.get(&"weed", 0), state.inventory.get(&"coke", 0)])
	if weed == 6 and lab.product == &"coke" and coke == 5 and me.cash == 1000 - 40 - 300 and state.inventory.get(&"weed", 0) == 6 and state.inventory.get(&"coke", 0) == 5:
		print("DRUGS_VERIFY: PASS")
		quit()
	else:
		print("DRUGS_VERIFY: FAIL - recipes, switching, collecting")
		quit(1)
