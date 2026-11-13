## B6: weapons wear with use (a hit more than a miss), worn blades and bats
## hit softer and finally break (back to fists), worn pistols jam (the next
## pull clears it), and a workshop fixes them for part of the price.
extends SceneTree

func _initialize() -> void:
	var st := PlayerStateData.new()
	st.inventory = {&"bat": 1}
	st.weapon = &"bat"
	var ok := is_equal_approx(WeaponWear.damage_mult(st), 1.0)
	WeaponWear.use(st, true)
	var after_hit := WeaponWear.condition(st, &"bat")
	WeaponWear.use(st, false)
	ok = ok and after_hit < 1.0 and 1.0 - after_hit > after_hit - WeaponWear.condition(st, &"bat")
	st.wear[&"bat"] = 0.5
	ok = ok and WeaponWear.damage_mult(st) < 1.0 and WeaponWear.repair_cost(st, &"bat") == roundi(45 * 0.5 * 0.5)
	st.wear[&"bat"] = 0.01
	ok = ok and WeaponWear.use(st, true) == "broke" and st.weapon == &"fists" and not st.inventory.has(&"bat")
	# Jams: a worn pistol jams sometimes, a new one never.
	var p := PlayerStateData.new()
	p.inventory = {&"pistol": 1}
	p.weapon = &"pistol"
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var new_jams := 0
	for i in 200:
		new_jams += int(WeaponWear.jams(p, rng))
	p.wear[&"pistol"] = 0.1
	var worn_jams := 0
	for i in 200:
		worn_jams += int(WeaponWear.jams(p, rng))
	ok = ok and new_jams == 0 and worn_jams > 20
	# Fixing at a workshop.
	var world := World.new()
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	me.cash = 500
	var e := Entity.new(me.id)
	e.add_component(me)
	e.add_component(p)
	world.register_entity(e)
	var shop := BuildingData.new()
	var cost := WeaponWear.repair_cost(p, &"pistol")
	var r := WeaponWear.repair(world, me, p, &"pistol", shop)
	ok = ok and r["ok"] and me.cash == 500 - cost and shop.cash_on_hand == cost and is_equal_approx(WeaponWear.condition(p, &"pistol"), 1.0)
	ok = ok and ItemCard.lines(&"pistol", p).any(func(l: Array) -> bool: return l[0] == "bar" and l[1] == "Condition")
	print("worn pistol jammed %d of 200; fix cost $%d" % [worn_jams, cost])
	print("WEAPON_WEAR_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
