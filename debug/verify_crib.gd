## CR1 validator: upgrading costs money and needs the rank; a Pad rests you
## faster; the Spot's safe halves what an arrest takes and its crew hangout
## raises loyalty each morning; the Stash house keeps a finished score as a
## trophy, keeps your name known, and cleans a little dirty money overnight.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	me.cash = 100
	ok = _check(CribSystem.upgrade(w, state).get("reason", "") == "cant_afford" and state.crib == 0, "no money, no upgrade") and ok
	me.cash = 700
	ok = _check(CribSystem.upgrade(w, state).get("ok", false) and state.crib == 1 and me.cash == 100, "$600 buys the Pad") and ok
	ok = _check(CribSystem.rest_mult(state) > 1.0, "the Pad rests you faster") and ok
	me.cash = 5000
	ok = _check(CribSystem.upgrade(w, state).get("reason", "") == "crib_rank" and state.crib == 1, "the Spot needs Soldier") and ok
	state.rank = 2
	ok = _check(CribSystem.upgrade(w, state).get("ok", false) and state.crib == 2, "a Soldier buys the Spot") and ok

	var cops := w.find_system(CopAISystem) as CopAISystem
	me.cash = 1000
	state.dirty_cash = 1000
	state.law_tier = GanstoidEnums.LawTier.WARNED
	cops._arrest(me, state)
	var with_safe := 1000 - me.cash
	state.crib = 1
	me.cash = 1000
	state.dirty_cash = 1000
	state.law_tier = GanstoidEnums.LawTier.WARNED
	cops._arrest(me, state)
	var without := 1000 - me.cash
	print("an arrest takes $%d with the safe, $%d without" % [with_safe, without])
	ok = _check(with_safe > 0 and with_safe * 2 <= without + 1, "the safe halves what an arrest takes") and ok

	state.crib = 2
	var mate: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != me and not (n.is_cop or n.is_dealer) and n.gang_id == &"":
			mate = n
			break
	mate.is_crew = true
	mate.loyalty = 0.5
	state.crew_ids.append(mate.id)
	CribSystem.morning(w, state)
	ok = _check(mate.loyalty > 0.5, "the crew hangout raises loyalty") and ok

	state.crib = 3
	CribSystem.add_trophy(state, "jewellery store", 1000, 3)
	state.fame = 10.0
	me.cash = 1000
	state.dirty_cash = 500
	CribSystem.morning(w, state)
	print("stash house morning: fame %.0f, dirty $%d, cash $%d" % [state.fame, state.dirty_cash, me.cash])
	ok = _check(state.fame > 10.0 and state.dirty_cash == 200 and me.cash == 1000 - int(CribSystem.LAUNDER_PER_DAY * CribSystem.LAUNDER_FEE), "trophies keep your name known; money is cleaned overnight for a fee") and ok
	ok = _check(CribSystem.upgrade(w, state).get("reason", "") == "crib_max", "nothing above the Stash house") and ok
	if ok:
		print("CRIB_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("CRIB_VERIFY: FAIL - ", what)
	return good
