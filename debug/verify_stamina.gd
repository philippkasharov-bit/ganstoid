## ST1: running tires you out, then you can't run until you catch your breath;
## standing recovers fastest; a heavy bag slows you and tires you faster;
## winded blows are weaker; the breath moodle shows it.
extends SceneTree

func _run(st: PlayerStateData, seconds: float, running: bool, moving: bool) -> void:
	for i in int(seconds * 10):
		Stamina.update(st, running and Stamina.can_run(st), moving, 0.1)

func _initialize() -> void:
	var st := PlayerStateData.new()
	_run(st, 10.0, true, true)
	var ok := st.endurance < 0.4 and not st.winded and Stamina.can_run(st)
	_run(st, 5.0, true, true)
	ok = ok and st.winded and not Stamina.can_run(st) and is_equal_approx(Stamina.damage_mult(st), Stamina.WINDED_DAMAGE)
	var low := st.endurance
	_run(st, 2.0, false, false)
	ok = ok and st.endurance > low + 0.1 and st.winded   # recovering, still winded under CATCH_AT
	_run(st, 3.0, false, false)
	ok = ok and not st.winded and Stamina.can_run(st)
	var light := PlayerStateData.new()
	var heavy := PlayerStateData.new()
	heavy.inventory = {&"bat": 20}   # 20 kg
	ok = ok and Stamina.heavy(heavy) and is_equal_approx(Stamina.speed_mult(heavy), Stamina.HEAVY_SPEED) and not Stamina.heavy(light)
	_run(light, 5.0, true, true)
	_run(heavy, 5.0, true, true)
	ok = ok and heavy.endurance < light.endurance
	Stamina.swing(light)
	var npc := NPCData.new()
	var names: Array = Moodles.list(npc, heavy).map(func(m: Array) -> String: return m[1])
	ok = ok and names.has("Heavy Load") and (names.has("Winded") or names.has("Out of Breath") or names.has("Exhausted") or names.has("Spent"))
	print("STAMINA_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
