## HB1: the hotbar fills from what you carry (weapons, then the best bandage,
## food, drink); a press holds a weapon, again puts it away, or uses an item.
extends SceneTree

func _initialize() -> void:
	var st := PlayerStateData.new()
	var ok := Hotbar.slots(st).is_empty() and Hotbar.press(st, 0).is_empty()
	st.inventory = {&"knife": 1, &"pistol": 1, &"bandage": 3, &"chips": 1, &"burrito": 1, &"water": 2, &"weed": 5}
	var s := Hotbar.slots(st)
	var ids: Array = s.map(func(x: Dictionary) -> StringName: return x["id"])
	ok = ok and ids == [&"knife", &"pistol", &"bandage", &"burrito", &"water"]   # best food is the burrito
	ok = ok and Hotbar.press(st, 0) == {"use": &"knife"} and Hotbar.press(st, 9).is_empty()
	st.weapon = &"knife"
	ok = ok and Hotbar.in_hand(st, s[0]) and Hotbar.press(st, 0) == {"holster": true}
	ok = ok and Hotbar.press(st, 2) == {"use": &"bandage"}
	print("HOTBAR_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
