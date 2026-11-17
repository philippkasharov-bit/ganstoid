## AD1: the admin panel's bug test: quick checks on the game as it is right
## now (they only read, nothing changes). Each is [name, ok, what it found].
## The full checks are the debug/verify_*.gd scripts (debug/TESTS.md); these
## catch a broken state in a running game, where those cannot look.
class_name AdminTests
extends RefCounted

static func run_all(world: World) -> Array:
	var out: Array = []
	var p: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return [["player exists", false, "no player entity"]]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	out.append(["player position is a real place", is_finite(me.position.x) and is_finite(me.position.y) and me.position.x >= -100.0 and me.position.y >= -100.0, str(me.position.round())])
	out.append(["health and needs in 0..1", _in01([me.health, me.hunger, me.thirst, me.fatigue]), "hp %.2f food %.2f water %.2f rest %.2f" % [me.health, me.hunger, me.thirst, me.fatigue]])
	var bad_items := state.inventory.keys().filter(func(k: StringName) -> bool: return int(state.inventory[k]) < 0 or not ItemCatalog.ITEMS.has(k))
	out.append(["bag holds only real items, no negatives", bad_items.is_empty(), "ok" if bad_items.is_empty() else str(bad_items)])
	out.append(["cash is not negative, dirty <= cash", me.cash >= 0 and state.dirty_cash <= me.cash, "$%d (dirty $%d)" % [me.cash, state.dirty_cash]])
	var fields := SaveGame._fields(state)
	var back: Variant = str_to_var(var_to_str(fields))
	out.append(["your state survives a save and load", typeof(back) == TYPE_DICTIONARY and (back as Dictionary).size() == fields.size(), "%d fields" % fields.size()])
	var bad_h := state.hustles.filter(func(h: Dictionary) -> bool: return not HustleSystem.KINDS.has(h.get("kind", "")))
	out.append(["today's hustles are valid", bad_h.is_empty() and state.hustles.size() <= HustleSystem.PER_DAY, "%d hustles" % state.hustles.size()])
	var gone := state.rivals.values().filter(func(r: Dictionary) -> bool: return not world.entities.has(r.get("npc", &"")))
	out.append(["every rival is a real person", gone.is_empty(), "%d rivals" % state.rivals.size()])
	out.append(["map fog is the right size", state.explored.is_empty() or state.explored.size() == ExplorationSystem.GRID * ExplorationSystem.GRID / 8, "%d cells explored" % ExplorationSystem.count(state)])
	out.append(["phone inbox within its limit", state.inbox.size() <= PhoneSystem.INBOX_MAX, "%d messages" % state.inbox.size()])
	if state.waypoint != Vector2.INF:
		out.append(["GPS finds a route to your waypoint", MiniMap.gps_route(me.position, state.waypoint).size() >= 2, "%d m" % roundi(me.position.distance_to(state.waypoint))])
	out.append(["walk mesh ready", SimNav.active != null and SimNav.active.usable(), "navigation"])
	var missing: Array = []
	for cls in [NeedsSystem, RankSystem, JobSystem, HustleSystem, NewsSystem, RivalSystem, PhoneSystem, CornerWarSystem, ExplorationSystem, ReactionSystem, PickpocketSystem, AdminSystem]:
		if world.find_system(cls) == null:
			missing.append(cls.get_global_name())
	out.append(["all game systems running", missing.is_empty(), "ok" if missing.is_empty() else str(missing)])
	var fps := Engine.get_frames_per_second()
	out.append(["frame rate OK (30+)", fps >= 30 or fps == 0, "%d fps" % fps])
	var npcs := world.get_entities_with_component(ComponentNames.NPC).size()
	out.append(["the city is populated", npcs > 1000, "%d people" % npcs])
	return out

static func _in01(values: Array) -> bool:
	for v in values:
		if not (float(v) >= 0.0 and float(v) <= 1.0):
			return false
	return true
