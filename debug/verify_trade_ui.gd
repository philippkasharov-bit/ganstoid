## UI7 validator: who someone is to you (crew, police, a friend, a scared
## victim, an enemy, a stranger: no ring); the deal window opens on a person,
## sets your price and makes offers; the pawn window sells one valuable or
## all at the pawn rate; walking away closes it.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS
	w.tick = SimClock.hours(36.0)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var trade := w.find_system(TradeSystem) as TradeSystem
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	var ok := true
	var ppl := []
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_crew or n.is_dealer or n.is_fixer or n.is_down) and n.gang_id == &"":
			ppl.append(n)
			if ppl.size() == 5:
				break
	ok = _check(Relation.of(w, state, ppl[0]).is_empty(), "a stranger: no ring") and ok
	ppl[1].is_crew = true
	MemorySystem.remember(w, state, ppl[2].id, "helped")
	MemorySystem.remember(w, state, ppl[3].id, "robbed")
	MemorySystem.remember(w, state, ppl[4].id, "robbed")
	ppl[4].fear = 1.0
	var labels := []
	for i in range(1, 5):
		labels.append(Relation.of(w, state, ppl[i])[1])
	print("rings: ", labels)
	ok = _check(Relation.of(w, state, ppl[1])[0] == Relation.CREW and Relation.of(w, state, ppl[2])[0] == Relation.FRIEND and Relation.of(w, state, ppl[3])[0] == Relation.ENEMY and Relation.of(w, state, ppl[4])[0] == Relation.SCARED, "crew blue, friend green, the one you robbed red, a scared one yellow") and ok
	var cop: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		if (e.get_component(ComponentNames.NPC) as NPCData).is_cop:
			cop = e.get_component(ComponentNames.NPC)
			break
	ok = _check(Relation.of(w, state, cop)[1] == "Police", "police are marked") and ok
	# the deal window
	var buyer: NPCData = ppl[0]
	me.position = buyer.position + Vector2(1, 0)
	w.reindex_position(me.id)
	state.inventory[&"weed"] = 20
	TradeSystem.open(state, "deal", buyer.id)
	state.ui_trade = {"op": "price", "good": &"weed", "set": 27}
	trade.process_entities(players, 0.0, w.tick)
	ok = _check(not state.trade.is_empty() and int(state.prices[&"weed"]) == 27, "the deal window sets your price") and ok
	state.ui_trade = {"op": "offer", "good": &"weed"}
	trade.process_entities(players, 0.0, w.tick)
	ok = _check(String(state.trade.get("line", "")) != "" and int(state.trade.get("tone", 0)) != 0, "an offer gets an answer: \"%s\"" % state.trade.get("line", "")) and ok
	me.position = buyer.position + Vector2(20, 0)
	trade.process_entities(players, 0.0, w.tick)
	ok = _check(state.trade.is_empty(), "walk away and it closes") and ok
	# the pawn window
	var pawn: BuildingData = null
	for b in BusinessSystem.all_buildings(w):
		if b.trade == &"pawn shop":
			pawn = b
			break
	me.position = pawn.position
	state.inventory = {&"watch": 2, &"tv": 1}
	me.cash = 0
	state.dirty_cash = 0
	TradeSystem.open(state, "pawn", pawn.id)
	state.ui_trade = {"op": "sell", "id": &"watch"}
	trade.process_entities(players, 0.0, w.tick)
	ok = _check(int(state.inventory[&"watch"]) == 1 and me.cash == roundi(150 * Fence.PAWN_SHARE), "sell one watch at the pawn shop ($%d)" % me.cash) and ok
	state.ui_trade = {"op": "sell_all"}
	trade.process_entities(players, 0.0, w.tick)
	ok = _check(state.inventory.is_empty() and state.dirty_cash == 0, "sell the rest, all clean ($%d)" % me.cash) and ok
	state.ui_trade = {"op": "close"}
	trade.process_entities(players, 0.0, w.tick)
	ok = _check(state.trade.is_empty(), "close") and ok
	if ok:
		print("TRADE_UI_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	print(("  ok   " if good else "  FAIL ") + what)
	if not good:
		print("TRADE_UI_VERIFY: FAIL - " + what)
	return good
