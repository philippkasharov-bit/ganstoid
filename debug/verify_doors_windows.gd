## DW2: ways in, what each leaves behind, boards stop a window, fixed by restock.
extends SceneTree

func _initialize() -> void:
	var house := BuildingData.new()
	var ok: bool = StreetCrime.ways_in(house).size() == 3
	house.windows_boarded = true
	ok = ok and StreetCrime.ways_in(house).size() == 2   # no window through boards
	house.windows_boarded = false
	house.door_kicked = true
	var ways := StreetCrime.ways_in(house)
	ok = ok and ways.size() == 1 and ways[0][0] == "walk"
	ok = ok and StreetCrime.WAYS_IN["window"][1] > StreetCrime.WAYS_IN["kick"][1] and StreetCrime.WAYS_IN["kick"][1] > StreetCrime.WAYS_IN["pick"][1]   # louder
	ok = ok and StreetCrime.WAYS_IN["pick"][0] > StreetCrime.WAYS_IN["kick"][0]   # quieter is slower
	var world := World.new()
	world.tick = int(SimClock.day_ticks * 10)
	house.looted_tick = 0
	house.windows_broken = 2
	StreetCrime.fix_up(world, house)
	ok = ok and not house.door_kicked and house.windows_broken == 0
	print("DOORS_WINDOWS_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
