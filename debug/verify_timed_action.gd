## TA1: using an item takes time, finishes on its own, and moving breaks it off
## without using anything up.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var npc := NPCData.new()
	npc.hunger = 0.2
	var st := PlayerStateData.new()
	st.inventory = {&"burrito": 2}
	var ok := TimedAction.start(world, st, &"burrito").is_empty() and not st.timed.is_empty()
	world.tick += SimClock.real_seconds(1.0)
	ok = ok and TimedAction.advance(world, npc, st, false).is_empty() and npc.hunger == 0.2   # still eating
	ok = ok and absf(TimedAction.progress(world, st)["f"] - 1.0 / 3.0) < 0.02
	world.tick += SimClock.real_seconds(2.1)
	var done := TimedAction.advance(world, npc, st, false)
	ok = ok and done.get("ok", false) and npc.hunger > 0.6 and st.inventory[&"burrito"] == 1
	TimedAction.start(world, st, &"burrito")
	var cut := TimedAction.advance(world, npc, st, true)   # walked off mid-bite
	ok = ok and cut.get("reason", "") == "interrupted" and st.inventory[&"burrito"] == 1 and st.timed.is_empty()
	ok = ok and TimedAction.start(world, st, &"ammo").get("reason", "") == "dont_have"
	print("TIMED_ACTION_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
