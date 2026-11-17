## NB2b validator: free-time choice by score (ActivityChooser, ActivityPlaces).
##   - needs drive it: a hungry person eats, a worn-out one stays in at night
##   - closed or unreachable activities are never offered
##   - character bends it: the sociable like a night out more
##   - being broke makes paid things unlikely
##   - the same person, day and wake always choose the same; days differ
##   - across the real city at noon the picks are varied, and scoring is cheap
##   - the People tab lists the choices
extends SceneTree

const SEED := 4242
const SAMPLE := 400

func _initialize() -> void:
	if not _check_needs() or not _check_character():
		return
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, SEED)
	w.tick = SimClock.hours(36.0)   # day 2, noon
	if not _check_city(w):
		return
	_check_inspector(w)

func _flat(v: float, n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(v)
	return a

func _top(traits: PackedFloat32Array, drives: PackedFloat32Array, hour: float, cash: int) -> StringName:
	var best := &""
	var best_s := 0.0
	for id in Activities.TABLE:
		if Activities.is_open(id, hour) and id != &"visit_friend":
			var s: float = ActivityChooser.score(id, traits, drives, hour, 150.0, cash, false)[0]
			if s > best_s:
				best = id
				best_s = s
	return best

func _check_needs() -> bool:
	var plain := _flat(0.5, NPCMind.TRAITS)
	var hungry := _flat(0.9, NPCMind.DRIVES)
	hungry[GanstoidEnums.MindDrive.FOOD] = 0.05
	var worn := _flat(0.9, NPCMind.DRIVES)
	worn[GanstoidEnums.MindDrive.ENERGY] = 0.05
	worn[GanstoidEnums.MindDrive.SAFETY] = 0.3
	print("hungry at 13:00 -> %s; worn out at 23:30 -> %s" % [_top(plain, hungry, 13.0, 100), _top(plain, worn, 23.5, 100)])
	var broke: float = ActivityChooser.score(&"eat", plain, hungry, 13.0, 150.0, 0, false)[0]
	var flush: float = ActivityChooser.score(&"eat", plain, hungry, 13.0, 150.0, 100, false)[0]
	return _check(_top(plain, hungry, 13.0, 100) == &"eat", "a hungry person eats") \
		and _check(_top(plain, worn, 23.5, 100) == &"stay_in", "a worn-out person stays in at night") \
		and _check(broke < flush * 0.5, "being broke makes paying unlikely")

func _check_character() -> bool:
	var drives := _flat(0.6, NPCMind.DRIVES)
	var shy := _flat(0.5, NPCMind.TRAITS)
	shy[GanstoidEnums.MindTrait.SOCIABLE] = 0.1
	var party := shy.duplicate()
	party[GanstoidEnums.MindTrait.SOCIABLE] = 0.9
	var a: float = ActivityChooser.score(&"night_out", shy, drives, 21.0, 150.0, 100, false)[0]
	var b: float = ActivityChooser.score(&"night_out", party, drives, 21.0, 150.0, 100, false)[0]
	var why: String = ActivityChooser.score(&"night_out", party, drives, 21.0, 150.0, 100, false)[1]
	print("night out: shy %.3f, sociable %.3f (%s)" % [a, b, why])
	return _check(b > a * 1.5 and why.contains("sociable"), "the sociable like a night out more, and it says so")

func _check_city(w: World) -> bool:
	var places := ActivityPlaces.new()
	var mix := {}
	var changed := 0
	var t0 := Time.get_ticks_usec()
	var n := 0
	for id in w.entities:
		var npc: NPCData = w.entities[id].get_component(ComponentNames.NPC)
		if npc == null or id == PlayerFactory.PLAYER_ENTITY_ID or n >= SAMPLE:
			continue
		n += 1
		var mind := NPCMind.mind_of(w.entities[id], w.tick)
		var where := places.for_person(w, npc, mind)
		var scored := ActivityChooser.score_all(npc, mind, w.tick, where)
		for s in scored:
			if not Activities.is_open(s["id"], 12.0) or not where.has(s["id"]):
				return _check(false, "only open, reachable activities are offered")
		var today := ActivityChooser.pick(scored, id, 2, 0)
		if today != ActivityChooser.pick(scored, id, 2, 0):
			return _check(false, "the same day and wake pick the same")
		for day in range(3, 9):
			if ActivityChooser.pick(scored, id, day, 0) != today:
				changed += 1
				break
		mix[today] = mix.get(today, 0) + 1
	var us := float(Time.get_ticks_usec() - t0) / n
	print("noon picks over %d people: %s; %d choose differently on another day; %.0f us a person (first time, places included)" % [n, mix, changed, us])
	var biggest: int = mix.values().max()
	return _check(mix.size() >= 4 and biggest < n * 0.6, "noon picks are varied") \
		and _check(changed > n / 3, "the same person does not do the same every day") \
		and _check(us < 2000.0, "scoring stays cheap")

func _check_inspector(w: World) -> void:
	var id: StringName = &""
	for e in w.get_entities_with_component(ComponentNames.NPC):
		if e != PlayerFactory.PLAYER_ENTITY_ID:
			id = e
			break
	var info := NPCInspectorModel.describe(w, id, false, ActivityPlaces.new())
	print("People tab choices: ", info["choices"])
	if not _check(info["choices"].size() >= 2 and info["choices"].size() <= 5 and str(info["choices"]).contains("<- picks"), "the People tab lists the choices and the pick"):
		return
	if not _check(w.get_entities_with_component(ComponentNames.NPC_MIND).is_empty(), "choosing changes nothing"):
		return
	print("ACTIVITY_CHOOSER_VERIFY: PASS")
	quit(0)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("ACTIVITY_CHOOSER_VERIFY: FAIL - ", what)
		quit(1)
	return good
