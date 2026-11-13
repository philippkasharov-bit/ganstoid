## HT1: everyday lines float over your head (green good, red bad); big news
## (arrested, a new rank) is flagged for the pop-up instead.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var st := PlayerStateData.new()
	StreetTalk.say(world, st, {"ok": false, "reason": "dont_have"})
	var ok := st.message_tone == -1 and not st.message_alert and st.message_serial == 1
	StreetTalk.say_key(world, st, "arrested")
	ok = ok and st.message_alert and st.message_tone == 0
	var lines := HaloText.split_lines("Five-oh tore up the spot and took every last pack you had stashed in the back room")
	ok = ok and lines.size() >= 2
	var h := HaloText.new()
	h.push("You don't have that.", -1)
	ok = ok and h._lines.size() == 1 and h._lines[0]["colour"] == HaloText.TONES[-1]
	h.free()
	print("HALO_TEXT_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
