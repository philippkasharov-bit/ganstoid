## Z2: Zomboid's time controls. Fast-forward drops back to 1x the moment you
## are hurt, bleeding, wanted, aiming or in a menu, and says why; the clock
## shows paused / the speed / the reason.
extends SceneTree

func _initialize() -> void:
	var npc := NPCData.new()
	var st := PlayerStateData.new()
	var D = load("res://core/world_driver.gd")
	var ok: bool = D.fast_forward_blocker(npc, st, 1.0) == ""
	npc.health = 0.9
	ok = ok and D.fast_forward_blocker(npc, st, 1.0) == "you're hurt"
	ok = ok and D.fast_forward_blocker(npc, st, 0.9) == ""
	npc.bleeding = true
	ok = ok and D.fast_forward_blocker(npc, st, 0.9) == "you're bleeding"
	npc.bleeding = false
	st.law_tier = 1
	ok = ok and D.fast_forward_blocker(npc, st, 0.9) == "the police are looking"
	st.law_tier = 0
	st.aiming = true
	ok = ok and D.fast_forward_blocker(npc, st, 0.9) == "weapon up"
	st.aiming = false
	st.inventory_open = true
	ok = ok and D.fast_forward_blocker(npc, st, 0.9) == "a menu is open"
	ok = ok and ClockBox.speed_text(true, 1, "") == "Paused  (F3 to go on)" and ClockBox.speed_text(false, 20, "") == ">> 20x"
	ok = ok and ClockBox.speed_text(false, 1, "you're hurt") == "Back to 1x: you're hurt" and ClockBox.speed_text(false, 1, "") == ""
	print("TIME_CONTROLS_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
