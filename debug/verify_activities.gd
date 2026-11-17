## NB2a validator: the free-time activities table (data/npc/activities.gd).
##   - every activity has every field, with the right type and range
##   - trades are real (Jobs.TRADES), places and walks are known words
##   - every shop trade people can walk into offers something to do
##   - every need except money (work fills that) is filled by something
##   - the hours rule wraps past midnight
##   - in the real city, every shop activity has places to happen
extends SceneTree

const SEED := 4242
const FIELDS := ["label", "place", "walk", "hours", "stay", "trades", "fills", "likes", "cost", "appeal"]

func _initialize() -> void:
	for id in Activities.TABLE:
		var why := _bad_entry(id, Activities.TABLE[id])
		if not _check(why == "", "%s: %s" % [id, why]):
			return
	if not _check_coverage() or not _check_hours():
		return
	_check_city()

func _bad_entry(id: StringName, a: Dictionary) -> String:
	for f in FIELDS:
		if not a.has(f):
			return "missing " + f
	if not Activities.PLACES.has(a["place"]) or not Activities.WALKS.has(a["walk"]):
		return "unknown place or walk"
	if (a["place"] == "shop") != not a["trades"].is_empty():
		return "a shop activity lists trades, and only it"
	for t in a["trades"]:
		if not Jobs.TRADES.has(t) or Jobs.TRADES[t][0] != &"shop":
			return "trade %s is not a shop in Jobs.TRADES" % t
	var h: Array = a["hours"]
	var s: Array = a["stay"]
	if h[0] < 0.0 or h[0] > 24.0 or h[1] < 0.0 or h[1] > 24.0 or s[0] < 0.0 or s[0] > s[1]:
		return "hours or stay out of range"
	if a["walk"] in ["visit", "linger", "none"] and s[1] <= 0.0:
		return "a visit, linger or stay-in needs a stay"
	for k in a["fills"]:
		if k < 0 or k >= NPCMind.DRIVES or absf(a["fills"][k]) > 1.0:
			return "fills a need that does not exist, or by more than 1"
	for k in a["likes"]:
		if k < 0 or k >= NPCMind.TRAITS or absf(a["likes"][k]) > 1.0:
			return "likes a trait that does not exist, or by more than 1"
	if a["appeal"] <= 0.0 or a["appeal"] > 5.0:
		return "appeal out of range"
	return "" if a["cost"] >= 0 else "negative cost"

func _check_coverage() -> bool:
	for t in Jobs.TRADES:
		if Jobs.TRADES[t][0] == &"shop" and not Activities.PRIVATE_TRADES.has(t) and Activities.at_trade(t).is_empty():
			return _check(false, "shop trade %s offers nothing to do" % t)
	var filled := {}
	for id in Activities.TABLE:
		for k in Activities.TABLE[id]["fills"]:
			if Activities.TABLE[id]["fills"][k] > 0.0:
				filled[k] = true
	for k in NPCMind.DRIVES:
		if k != GanstoidEnums.MindDrive.MONEY and not filled.has(k):
			return _check(false, "nothing fills need %s" % GanstoidEnums.MindDrive.keys()[k])
	print("a diner offers: ", Activities.at_trade(&"diner"))
	return true

func _check_hours() -> bool:
	return _check(Activities.is_open(&"night_out", 23.5) and Activities.is_open(&"night_out", 1.0) \
		and not Activities.is_open(&"night_out", 12.0) and Activities.is_open(&"coffee", 7.0) \
		and not Activities.is_open(&"coffee", 15.0) and Activities.is_open(&"stay_in", 3.0), "hours wrap past midnight")

func _check_city() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, SEED)
	var places := {}
	for entity in w.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = entity.get_component(ComponentNames.BUILDING)
		for id in Activities.at_trade(b.trade):
			places[id] = places.get(id, 0) + 1
	print("places per activity in the city: ", places)
	for id in Activities.TABLE:
		if Activities.TABLE[id]["place"] == "shop" and places.get(id, 0) == 0:
			_check(false, "%s has nowhere to happen in the city" % id)
			return
	print("ACTIVITIES_VERIFY: PASS")
	quit(0)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("ACTIVITIES_VERIFY: FAIL - ", what)
		quit(1)
	return good
