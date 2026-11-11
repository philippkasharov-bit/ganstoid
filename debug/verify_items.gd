## G1 validator: items and counters.
##   1. A shop sells food at its price in opening hours, refuses at night and
##      when you are broke; the till takes the money.
##   2. A dealer sells a pistol and rounds at any hour; a workshop sells a bat.
##   3. Q only cycles through weapons you carry.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	me.cash = 560
	var state := PlayerStateData.new()
	state.rank = RankSystem.GUN_RANK   # RK1: dealers sell guns to Hustlers and up
	var p := Entity.new(me.id)
	p.add_component(me)
	p.add_component(state)
	world.register_entity(p)
	var day_id := _find_id(false)
	var night_id := _find_id(true)
	var shop := _building(world, day_id, &"shop")
	_building(world, night_id, &"shop")
	var hard := _building(world, &"hw1", &"workshop")
	var dealer := Entity.new(&"d1")
	var dn := NPCData.new()
	dn.id = &"d1"
	dn.is_dealer = true
	dealer.add_component(dn)
	world.register_entity(dealer)
	world.tick = SimClock.hours(12.0)
	var r1 := ShopSystem.buy(world, me, state, day_id, &"burrito")
	var wrong := ShopSystem.buy(world, me, state, day_id, &"pistol")
	world.tick = SimClock.hours(23.5)
	var night := ShopSystem.buy(world, me, state, day_id, &"water")
	var all_night := ShopSystem.buy(world, me, state, night_id, &"water")
	var gun := ShopSystem.buy(world, me, state, &"d1", &"pistol")
	var rounds := ShopSystem.buy(world, me, state, &"d1", &"ammo")
	world.tick = SimClock.hours(10.0)
	var bat := ShopSystem.buy(world, me, state, &"hw1", &"bat")
	var broke := ShopSystem.buy(world, me, state, &"hw1", &"knife")
	print("burrito %s, pistol at a shop %s, water at 23:30 %s, pistol at dealer %s, rounds %d, bat %s, knife broke %s, cash %d, till %d" % [
		r1.get("effect"), wrong.get("reason"), night.get("reason"), gun.get("effect"), state.ammo, bat.get("effect"), broke.get("reason"), me.cash, shop.cash_on_hand])
	var ok: bool = r1.get("ok") and wrong.get("reason") == "not_sold_here" and night.get("reason") == "closed" and all_night.get("ok", false)
	ok = ok and gun.get("ok") and state.ammo == 12 and bat.get("ok") and broke.get("reason") == "cant_afford"
	ok = ok and me.cash == 560 - 7 - 2 - 450 - 40 - 45 and shop.cash_on_hand == 107
	if not _check(ok, "counters sell what they stock, at their price, in their hours"):
		return
	var seen: Array = []
	for i in 4:
		seen.append(CombatSystem.cycle_weapon(state))
	print("Q cycles: %s" % [seen])
	if not _check(seen == [&"bat", &"pistol", &"fists", &"bat"], "Q cycles only through carried weapons"):
		return
	print("ITEMS_VERIFY: PASS")
	quit()

## A store id whose rolled hours are (or are not) round the clock, closing by 23:30.
func _find_id(all_night: bool) -> StringName:
	for i in 1000:
		var id := StringName("shop%d" % i)
		var h := ShopSystem.hours_of(id, "shop")
		if (h.y >= 24.0) == all_night and (all_night or h.y <= 23.0):
			return id
	return &""

func _building(world: World, id: StringName, kind: StringName) -> BuildingData:
	var e := Entity.new(id)
	var b := BuildingData.new()
	b.id = id
	b.building_type = GanstoidEnums.BuildingType.LEGIT_BUSINESS
	b.business_kind = kind
	b.cash_on_hand = 100
	e.add_component(b)
	world.register_entity(e)
	return b

func _check(good: bool, what: String) -> bool:
	if not good:
		print("ITEMS_VERIFY: FAIL - ", what)
		quit(1)
	return good
