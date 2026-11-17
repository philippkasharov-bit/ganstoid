## NB1b validator: the F11 People tab (NPCInspectorModel, NPCInspectorView).
##   - a click on someone's spot finds them; empty ground finds nobody
##   - the picture of a person has every section, with the right counts
##   - looking never changes the game: no mind is made, the tick stays
##   - their links (household, workmates) and what they think of you (ME1) show
##   - the tab draws in a window without errors
extends SceneTree

const SEED := 4242

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, SEED)
	w.tick = SimClock.hours(30.5)
	var id := _someone_with_home(w)
	var npc: NPCData = w.entities[id].get_component(ComponentNames.NPC)
	if not _check(NPCInspectorModel.person_at(w, npc.position + Vector2(0.5, 0), 3.0) != &"", "a click next to someone finds a person") \
		or not _check(NPCInspectorModel.person_at(w, Vector2(-99999, -99999), 3.0) == &"", "empty ground finds nobody"):
		return
	var state: PlayerStateData = w.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	state.memories[id] = {"deed": "robbed", "feel": -0.8, "day": 1, "n": 2, "reported": false}
	var tick := w.tick
	var info := NPCInspectorModel.describe(w, id)
	print("%s | %s | %s | about you: %s" % [info["name"], info["title"], info["tier"], info["about_you"]])
	print("links: ", info["links"])
	var ok: bool = info["traits"].size() == NPCMind.TRAITS and info["drives"].size() == NPCMind.DRIVES and info["mood"].size() == NPCMind.MOODS
	ok = ok and info["links"].size() == 4 and String(info["about_you"]).begins_with("robbed") and not info["stored"]
	if not _check(ok, "every section is there"):
		return
	if not _check(w.get_entities_with_component(ComponentNames.NPC_MIND).is_empty() and w.tick == tick, "looking changes nothing"):
		return
	var me: NPCData = w.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	me.home_building_id = npc.home_building_id
	var home_line: String = NPCInspectorModel.describe(w, id)["links"][0][1]
	if not _check(home_line.contains("you") and not home_line.contains(me.display_name), "the player living there shows as you"):
		return
	if not _check(not NPCInspectorModel.describe(w, id, false).has("links"), "links can be skipped on refresh"):
		return
	var mind := NPCMind.get_or_make(w, w.entities[id])
	NPCMind.remember(mind, GanstoidEnums.MindMemory.WAS_ROBBED, PlayerFactory.PLAYER_ENTITY_ID, npc.position, w.tick - SimClock.hours(3), 0.9)
	var lines: Array = NPCInspectorModel.describe(w, id)["memories"]
	print("memory: ", lines)
	if not _check(lines.size() == 1 and String(lines[0]).begins_with("Was robbed: you, 3 h ago"), "a memory reads in words"):
		return
	if not _check(NPCInspectorModel.tier(10) == "T0 full" and NPCInspectorModel.tier(2000) == "T3 abstract", "tiers by distance"):
		return
	_check_view(w, id)

func _check_view(w: World, id: StringName) -> void:
	NPCInspectorView.pinned = id
	var view := NPCInspectorView.new(w, func() -> void: pass)
	root.add_child(view)
	await process_frame
	var labels := view.find_children("*", "Label", true, false).size()
	print("the tab draws %d labels" % labels)
	if not _check(labels > 20, "the tab draws the person"):
		return
	print("NPC_INSPECTOR_VERIFY: PASS")
	quit(0)

func _someone_with_home(w: World) -> StringName:
	for id in w.entities:
		var npc: NPCData = w.entities[id].get_component(ComponentNames.NPC)
		if npc != null and id != PlayerFactory.PLAYER_ENTITY_ID and npc.home_building_id != &"":
			return id
	return &""

func _check(good: bool, what: String) -> bool:
	if not good:
		print("NPC_INSPECTOR_VERIFY: FAIL - ", what)
		quit(1)
	return good
