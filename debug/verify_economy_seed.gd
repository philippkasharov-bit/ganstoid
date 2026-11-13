## E1: a new city's money: every block has a wealth, budget, police funding
## and black market; workers have jobs paid by how rich their block is; homes
## hold what their people earn; businesses have a bank balance.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 4242)
	var data := BlockEconomyData.of(world)
	var ok := data != null and data.blocks.size() > 10
	var rich_pay := [0, 0]
	var poor_pay := [0, 0]
	var workers := 0
	var jobless_paid := 0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var npc: NPCData = e.get_component(ComponentNames.NPC)
		if npc.work_building_id == &"":
			jobless_paid += int(npc.wage > 0)
			continue
		workers += 1
		ok = ok and npc.job != &"" and npc.wage > 0
		var b: BuildingData = world.entities[npc.work_building_id].get_component(ComponentNames.BUILDING)
		var w: float = BlockEconomyData.block_at(world, b.position)["wealth"]
		var bucket: Array = rich_pay if w >= 0.5 else poor_pay
		bucket[0] += npc.wage
		bucket[1] += 1
	var homes_with_money := 0
	var empty_homes_with_money := 0
	var residents := {}
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		residents[e.get_component(ComponentNames.NPC).home_building_id] = true
	var biz_bank := 0
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.building_type == GanstoidEnums.BuildingType.RESIDENCE:
			homes_with_money += int(b.cash_on_hand > 0 or b.bank > 0)
			if not residents.has(b.id):
				empty_homes_with_money += int(b.cash_on_hand > 0 or b.bank > 0)
		elif b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			biz_bank += int(b.bank > 0)
	print("blocks %d, workers %d, avg pay rich block $%d (%d) poor block $%d (%d), homes with money %d, businesses banked %d" % [
		data.blocks.size(), workers, rich_pay[0] / maxi(1, rich_pay[1]), rich_pay[1], poor_pay[0] / maxi(1, poor_pay[1]), poor_pay[1], homes_with_money, biz_bank])
	ok = ok and workers > 50 and jobless_paid == 0 and homes_with_money > 40 and empty_homes_with_money == 0 and biz_bank > 0
	ok = ok and (rich_pay[1] == 0 or poor_pay[1] == 0 or rich_pay[0] / rich_pay[1] > poor_pay[0] / poor_pay[1])
	for c in data.blocks:
		var bl: Dictionary = data.blocks[c]
		ok = ok and bl["wealth"] > 0.0 and bl["wealth"] < 1.0 and is_equal_approx(bl["black"], 1.0 - bl["wealth"])
	# E1: trades fit their blocks; the homeless are out of work on poor blocks.
	var trades := {}
	var poor_trades := 0
	var poor_total := 0
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.building_type != GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			continue
		ok = ok and Jobs.TRADES.has(b.trade) and Jobs.TRADES[b.trade][0] == b.business_kind
		trades[b.trade] = true
		if BlockEconomyData.block_at(world, b.position)["wealth"] < 0.25:
			poor_total += 1
			poor_trades += int(float(Jobs.TRADES[b.trade][1]) <= 0.5)
	var homeless := 0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.home_building_id == &"" and n.camp != Vector2.ZERO:
			homeless += 1
			ok = ok and n.work_building_id == &"" and n.cash <= 12 and not n.indoors
	print("trades %d kinds, poor-block businesses fitting %d/%d, homeless %d" % [trades.size(), poor_trades, poor_total, homeless])
	ok = ok and trades.size() >= 8 and homeless > 0 and poor_trades == poor_total
	print("ECONOMY_SEED_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
