## E2: the daily money loop. Every dollar is accounted for: the city's total
## changes by exactly what came in from outside buyers minus what left (rent,
## restock, police pay). Workers get paid, shops sell, blocks collect tax,
## poor blocks fund their police worse than rich ones, and nobody goes negative.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 4242)
	var ok := true
	var start := EconomyFlow.total_money(world)
	EconomyFlow._index(world)   # the who-lives-where index is built once a session
	var t0 := Time.get_ticks_usec()
	var led := EconomyFlow.run_day(world)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var after := EconomyFlow.total_money(world)
	print("day 1: money %d -> %d, inflow %d, outflow %d, sales %d, wages %d, tax %d (%.1f ms)" % [start, after, led["inflow"], led["outflow"], led["sales"], led["wages"], led["tax"], ms])
	ok = ok and after == start + int(led["inflow"]) - int(led["outflow"])
	ok = ok and led["sales"] > 0 and led["wages"] > 0 and led["tax"] > 0
	var totals: Array = [after]
	for d in 29:
		var before := EconomyFlow.total_money(world)
		var l := EconomyFlow.run_day(world)
		var now := EconomyFlow.total_money(world)
		ok = ok and now == before + int(l["inflow"]) - int(l["outflow"])
		totals.append(now)
	var closed := 0
	var shops := 0
	for b in BusinessSystem.all_buildings(world):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			shops += 1
			closed += int(b.status == 2)
	print("30 days without crime: money %d -> %d, shops closed %d of %d" % [start, totals[-1], closed, shops])
	ok = ok and closed <= shops / 10   # a quiet city does not fall apart on its own
	ok = ok and totals[-1] > start * 0.5 and totals[-1] < start * 2.0   # steady, no runaway either way
	var negative := 0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		negative += int(e.get_component(ComponentNames.NPC).cash < 0)
	for b in BusinessSystem.all_buildings(world):
		negative += int(b.cash_on_hand < 0 or b.bank < 0)
	var rich := [0.0, 0]
	var poor := [0.0, 0]
	var data := BlockEconomyData.of(world)
	var by_wealth: Array = data.blocks.values()
	by_wealth.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["wealth"] < b["wealth"])
	var third := by_wealth.size() / 3
	for i in by_wealth.size():
		var bl: Dictionary = by_wealth[i]
		var bucket: Array = poor if i < third else (rich if i >= by_wealth.size() - third else [0.0, 0])
		bucket[0] += bl["police"]
		bucket[1] += 1
		negative += int(bl["budget"] < 0)
	print("police funding: rich blocks %.2f, poor blocks %.2f; negatives %d" % [rich[0] / maxi(1, rich[1]), poor[0] / maxi(1, poor[1]), negative])
	ok = ok and negative == 0 and (rich[1] == 0 or poor[1] == 0 or rich[0] / rich[1] > poor[0] / poor[1])
	ok = ok and ms < 30.0
	print("ECONOMY_FLOW_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
