## LT1: containers fill on first open (same roll on reload), empty out as you
## take, restock after the restock days; cash goes to your pocket; your own
## place has a stash only you fill.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var me := NPCData.new()
	var house := BuildingData.new()
	house.id = &"h1"
	house.building_type = GanstoidEnums.BuildingType.RESIDENCE
	var kinds := Containers.open(world, me, house)
	var ok: bool = kinds == ["kitchen", "bathroom", "bedroom"]
	var twin := BuildingData.new()
	twin.id = &"h1"
	twin.building_type = GanstoidEnums.BuildingType.RESIDENCE
	Containers.open(world, me, twin)
	ok = ok and str(twin.containers["kitchen"]["items"]) == str(house.containers["kitchen"]["items"])   # seeded: same roll
	var kitchen: Dictionary = house.containers["kitchen"]["items"]
	for id in kitchen.keys():
		Containers.take(world, house, "kitchen", id, 99)
	ok = ok and kitchen.is_empty()
	Containers.open(world, me, house)
	ok = ok and house.containers["kitchen"]["items"].is_empty()   # not restocked yet
	world.tick += int(LootTables.RESTOCK_DAYS * SimClock.day_ticks) + 1
	Containers.open(world, me, house)
	ok = ok and house.containers.has("kitchen")
	me.home_building_id = &"h1"
	ok = ok and Containers.open(world, me, house)[0] == Containers.STASH
	Containers.put(house, &"bandage", 2)
	ok = ok and house.containers[Containers.STASH]["items"][&"bandage"] == 2
	var shop := BuildingData.new()
	shop.building_type = GanstoidEnums.BuildingType.LEGIT_BUSINESS
	ok = ok and LootTables.containers_for(shop) == ["register", "stockroom"]
	print("CONTAINERS_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
