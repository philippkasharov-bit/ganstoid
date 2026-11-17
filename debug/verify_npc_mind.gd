## NB1a validator: who a person is inside (NPCMindData, NPCMind).
##   - a fresh city has no minds yet, and reading one does not add it (no play change)
##   - the same person is the same in two cities of the same seed
##   - people differ: traits spread out, and stay inside their archetype's range
##   - the archetypes people get match what they are (cops, gangs, homeless, jobs)
##   - needs run down and stop at 0; feelings fade back to calm
##   - memory keeps the 12 that matter most
##   - minds survive save and load (NB2d: written small, old saves still load),
##     and a broken saved mind is made safe
extends SceneTree

const PATH := "user://verify_npc_mind.txt"
const SEED := 4242
const SAMPLE := 400

func _initialize() -> void:
	var a := _city()
	if not _check(a.get_entities_with_component(ComponentNames.NPC_MIND).is_empty(), "a fresh city has no minds"):
		return
	var people := _people(a)
	var first: Entity = a.entities[people[0]]
	NPCMind.mind_of(first, a.tick)
	if not _check(not first.has_component(ComponentNames.NPC_MIND), "reading a mind does not add it"):
		return
	if not _check_rolls(a, people) or not _check_archetypes(a, people):
		return
	if not _check_time(first) or not _check_memory():
		return
	if not _check_save(a, people):
		return
	print("NPC_MIND_VERIFY: PASS")
	quit(0)

func _city() -> World:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, SEED)
	w.tick = SimClock.hours(30.5)
	return w

func _people(w: World) -> Array:
	var out := []
	for id in w.entities:
		if id != PlayerFactory.PLAYER_ENTITY_ID and w.entities[id].has_component(ComponentNames.NPC):
			out.append(id)
	return out

func _check_rolls(a: World, people: Array) -> bool:
	var b := _city()
	var sums := PackedFloat32Array()
	sums.resize(NPCMind.TRAITS)
	var squares := sums.duplicate()
	var seen := {}
	for i in mini(SAMPLE, people.size()):
		var entity: Entity = a.entities[people[i]]
		var t := NPCMind.traits(entity.id, NPCMind.mind_of(entity, a.tick))
		var t2 := NPCMind.traits(entity.id, NPCMind.mind_of(b.entities[people[i]], b.tick))
		if t != t2:
			return _check(false, "%s rolls the same in two cities of one seed" % entity.id)
		seen[str(t)] = true
		for k in NPCMind.TRAITS:
			sums[k] += t[k]
			squares[k] += t[k] * t[k]
	var n := float(mini(SAMPLE, people.size()))
	var spreads := []
	for k in NPCMind.TRAITS:
		var mean := sums[k] / n
		spreads.append(snappedf(sqrt(maxf(0.0, squares[k] / n - mean * mean)), 0.001))
	print("trait spread (std dev) over %d people: %s; distinct %d" % [n, spreads, seen.size()])
	return _check(seen.size() == int(n), "no two people share all traits") \
		and _check(spreads.min() > 0.08, "every trait varies between people")

func _check_archetypes(a: World, people: Array) -> bool:
	var counts := {}
	for id in people:
		var npc: NPCData = a.entities[id].get_component(ComponentNames.NPC)
		var kind := NPCMind.archetype_of(npc)
		counts[kind] = counts.get(kind, 0) + 1
		if npc.is_cop and kind != &"cop_on_beat":
			return _check(false, "a cop is a cop on the beat")
		var t := NPCMind.traits(id, NPCMind.make(npc, a.tick))
		for k in NPCMind.TRAITS:
			var span: Array = Archetypes.TABLE[kind]["traits"][k]
			if t[k] < span[0] - 0.0001 or t[k] > span[1] + 0.0001:
				return _check(false, "%s trait %d inside the %s range" % [id, k, kind])
	print("archetypes: ", counts)
	return _check(counts.size() >= 4, "at least 4 archetypes appear in the city")

func _check_time(entity: Entity) -> bool:
	var mind := NPCMind.make(entity.get_component(ComponentNames.NPC), 0)
	var later := NPCMind.drives_now(entity.id, mind, SimClock.hours(3))
	var much_later := NPCMind.drives_now(entity.id, mind, SimClock.hours(400))
	var ok := true
	for k in NPCMind.DRIVES:
		ok = ok and later[k] < mind.drives[k] and much_later[k] == 0.0
	NPCMind.set_drive(entity.id, mind, GanstoidEnums.MindDrive.FOOD, 1.0, SimClock.hours(3))
	ok = ok and NPCMind.drives_now(entity.id, mind, SimClock.hours(3))[GanstoidEnums.MindDrive.FOOD] == 1.0
	if not _check(ok, "needs run down, stop at 0, and eating fills food"):
		return false
	NPCMind.feel(mind, GanstoidEnums.MindMood.AFRAID, 0.9, 0)
	var soon := NPCMind.mood_now(mind, SimClock.hours(1))[GanstoidEnums.MindMood.AFRAID]
	var gone := NPCMind.mood_now(mind, SimClock.hours(12))
	print("fear 0.9 -> %.3f after 1 h -> %.4f after 12 h; calm %.3f" % [soon, gone[GanstoidEnums.MindMood.AFRAID], gone[GanstoidEnums.MindMood.CALM]])
	return _check(absf(soon - 0.45) < 0.01 and gone[GanstoidEnums.MindMood.AFRAID] < 0.001 \
		and absf(gone[GanstoidEnums.MindMood.CALM] - NPCMind.CALM_BASELINE) < 0.001, "feelings fade halfway each hour")

func _check_memory() -> bool:
	var mind := NPCMindData.new()
	for i in 20:
		NPCMind.remember(mind, GanstoidEnums.MindMemory.SAW_CRIME, &"x", Vector2(i, 0), i, float(i) / 20.0)
	NPCMind.remember(mind, GanstoidEnums.MindMemory.SAW_BODY, &"y", Vector2.ZERO, 99, 0.01)   # too small to keep
	var weights := Array(mind.mem_weight)
	weights.sort()
	return _check(mind.mem_kind.size() == NPCMind.MEMORY_CAP and weights[0] >= 8.0 / 20.0 - 0.001 \
		and not mind.mem_who.has("y"), "memory keeps the 12 that matter most")

func _check_save(a: World, people: Array) -> bool:
	var touched: Entity = a.entities[people[1]]
	var mind := NPCMind.get_or_make(a, touched)
	NPCMind.nudge_trait(mind, GanstoidEnums.MindTrait.PARANOID, 0.2)
	NPCMind.remember(mind, GanstoidEnums.MindMemory.WAS_ROBBED, PlayerFactory.PLAYER_ENTITY_ID, Vector2(5, 6), a.tick, 0.9)
	NPCMind.feel(mind, GanstoidEnums.MindMood.ANGRY, 0.7, a.tick)
	mind.habit_slots = PackedStringArray(["", "", "eat", "", "stroll", ""])
	var broken: Entity = a.entities[people[2]]
	NPCMind.get_or_make(a, broken)
	var old: Entity = a.entities[people[3]]
	var old_mind := NPCMind.get_or_make(a, old)
	NPCMind.feel(old_mind, GanstoidEnums.MindMood.HAPPY, 0.4, a.tick)
	if not _check(a.get_entities_with_component(ComponentNames.NPC_MIND).size() == 3, "a written mind is indexed"):
		return false
	var data := SaveGame.snapshot(a, SEED)
	data["entities"][broken.id][ComponentNames.NPC_MIND] = {MindPack.KEY: "%%not base64%%", "t": ["x", 5], "a": "alien",
		"h": "|".repeat(5000), "m": [1, 2, 3, 4, 5], "f": PackedStringArray(["a", "b", "c", "d", "e", "f"])}
	data["entities"][old.id][ComponentNames.NPC_MIND] = SaveGame._fields(old_mind)   # NB1's field-by-field form
	SaveGame._store(data, PATH)
	var b := _city()
	SaveGame.apply(b, SaveGame.read(PATH))
	var m2: NPCMindData = b.entities[touched.id].get_component(ComponentNames.NPC_MIND)
	var b2: NPCMindData = b.entities[broken.id].get_component(ComponentNames.NPC_MIND)
	var o2: NPCMindData = b.entities[old.id].get_component(ComponentNames.NPC_MIND)
	print("one mind written: %s" % var_to_str(data["entities"][touched.id][ComponentNames.NPC_MIND]).replace("\n", " "))
	print("fixed broken mind: %s drives %s, %d habits, %d friends, %d memories" % [b2.archetype, b2.drives, b2.habit_slots.size(), b2.friends.size(), b2.mem_kind.size()])
	var ok := m2 != null and _close(NPCMind.traits(touched.id, m2), NPCMind.traits(touched.id, mind))
	ok = ok and m2.mem_who == mind.mem_who and _close(m2.mem_weight, mind.mem_weight) and _close(m2.mood, mind.mood)
	ok = ok and _close(m2.drives, mind.drives) and m2.habit_slots == mind.habit_slots and m2.drives_tick == mind.drives_tick
	ok = ok and b.get_entities_with_component(ComponentNames.NPC_MIND).size() == 3
	if not _check(ok, "a mind read back is the mind written (to within 0.004)"):
		return false
	if not _check(o2 != null and _close(o2.mood, old_mind.mood), "a mind saved the old way still loads"):
		return false
	return _check(b2.archetype == Archetypes.DEFAULT and b2.drives.size() == NPCMind.DRIVES and b2.mem_kind.size() == 0 \
		and b2.habit_slots.size() == NPCMind.HABIT_SLOTS and b2.friends.size() == NPCMind.FRIENDS_CAP, "a broken saved mind is made safe")

func _close(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > 0.004:
			return false
	return true

func _check(good: bool, what: String) -> bool:
	if not good:
		print("NPC_MIND_VERIFY: FAIL - ", what)
		quit(1)
	return good
