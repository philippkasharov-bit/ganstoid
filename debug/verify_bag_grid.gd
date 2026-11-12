## INV1: items take cells by size, piles stack, the layout follows the counts,
## a full bag refuses more, and drag-and-drop only lands where it fits.
extends SceneTree

func _initialize() -> void:
	var st := PlayerStateData.new()
	st.inventory = {&"bat": 1, &"bandage": 7, &"water": 2}
	BagGrid.sync(st)
	var ok := _count(st, &"bandage") == 7 and _piles(st, &"bandage") == 2   # stack of 5 + 2
	ok = ok and _count(st, &"bat") == 1 and BagGrid.footprint(&"bat", false) == Vector2i(1, 4)
	var taken := BagGrid.occupancy(st.bag)
	ok = ok and taken.size() == 4 + 2 + 2 * 2   # bat 4 cells, 2 bandage piles, 2 waters of 2
	st.inventory[&"bandage"] = 3   # used four
	BagGrid.sync(st)
	ok = ok and _count(st, &"bandage") == 3 and _piles(st, &"bandage") == 1
	var full := PlayerStateData.new()
	full.inventory = {&"bat": BagGrid.COLS * BagGrid.ROWS / 4}   # 12 bats fill 48 cells
	BagGrid.sync(full)
	ok = ok and BagGrid.loose(full).is_empty() and BagGrid.room_for(full, &"chips") == 0
	full.inventory[&"bat"] += 1
	BagGrid.sync(full)
	ok = ok and BagGrid.loose(full).get(&"bat", 0) == 1   # one too many: shown as loose, not lost
	var mv := PlayerStateData.new()
	mv.inventory = {&"pistol": 1, &"chips": 1}
	BagGrid.sync(mv)
	ok = ok and not BagGrid.move(mv, 0, Vector2i(7, 0), false)   # 2 wide at the last column: no
	ok = ok and BagGrid.move(mv, 0, Vector2i(7, 0), true)        # turned upright: fits
	ok = ok and not BagGrid.move(mv, 1, Vector2i(7, 1), false)   # onto the pistol: no
	print("BAG_GRID_VERIFY: ", "PASS" if ok else "FAIL")
	quit()

func _count(st: PlayerStateData, id: StringName) -> int:
	var n := 0
	for p in st.bag:
		if p["id"] == id:
			n += int(p["n"])
	return n

func _piles(st: PlayerStateData, id: StringName) -> int:
	return st.bag.filter(func(p: Dictionary) -> bool: return p["id"] == id).size()
