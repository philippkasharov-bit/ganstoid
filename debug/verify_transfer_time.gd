## B4: moving things in or out of the bag takes a moment (longer when heavy),
## queues behind the one under way, and walking off cancels it.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var st := PlayerStateData.new()
	var npc := NPCData.new()
	var light := {"op": "drop", "id": &"chips", "n": 1}
	var heavy := {"op": "drop", "id": &"bat", "n": 1}
	var ok := TimedAction.move_seconds(heavy) > TimedAction.move_seconds(light) and TimedAction.move_seconds({"op": "drop", "id": &"bat", "n": 50}) == TimedAction.MOVE_MAX_S
	TimedAction.start_move(world, st, light)
	TimedAction.start_move(world, st, heavy)
	ok = ok and st.timed["queue"].size() == 1
	ok = ok and TimedAction.progress(world, st)["text"] == "Dropping"
	var done := {}
	for i in 2000:
		world.tick += 1
		var r := TimedAction.advance(world, npc, st, false)
		if r.has("do_move"):
			done = r
			break
	ok = ok and done["do_move"]["id"] == &"chips" and st.timed.get("move", {}).get("id", &"") == &"bat"   # the next one started
	var r2 := TimedAction.advance(world, npc, st, true)   # walked off
	ok = ok and r2.get("reason", "") == "interrupted" and st.timed.is_empty()
	print("TRANSFER_TIME_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
