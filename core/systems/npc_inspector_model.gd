## NB1b: everything the F11 People tab shows about one person, as plain data.
## Only reads the World (never writes, never makes a mind), so looking at
## someone cannot change the game. NPCInspectorView draws it.
class_name NPCInspectorModel
extends RefCounted

const FULL_DETAIL_M := 40.0   # NB plan tier T0: full detail this close (NB7 makes it real)
const LINKS_SHOWN := 4        # names listed per kind of link
const CHOICES_SHOWN := 5      # NB2b: free-time choices listed, best first

## The person nearest `at` within `radius_m`, or &"" (the player is skipped).
static func person_at(world: World, at: Vector2, radius_m: float) -> StringName:
	var best := &""
	var best_d := radius_m
	for id in world.spatial_index.query_nearby(at):
		var npc := _npc(world, id)
		if npc == null or id == PlayerFactory.PLAYER_ENTITY_ID:
			continue
		var d := npc.position.distance_to(at)
		if d <= best_d:
			best = id
			best_d = d
	return best

## Detail tier by distance from the player (the plan's T0-T3).
static func tier(distance_m: float) -> String:
	if distance_m <= FULL_DETAIL_M:
		return "T0 full"
	if distance_m <= NPCStreet.NEAR_M:
		return "T1 near"
	if distance_m <= NPCStreet.ABSTRACT_M:
		return "T2 far"
	return "T3 abstract"

## The whole picture of one person, or {} if they are gone. `with_links` walks
## everyone to find household and workmates, so callers ask for it once.
## `places` (NB2b) adds what they would choose to do with free time right now.
static func describe(world: World, id: StringName, with_links: bool = true, places: ActivityPlaces = null) -> Dictionary:
	var entity: Entity = world.entities.get(id)
	var npc: NPCData = entity.get_component(ComponentNames.NPC) if entity != null else null
	if npc == null:
		return {}
	var mind := NPCMind.mind_of(entity, world.tick)
	var me := _npc(world, PlayerFactory.PLAYER_ENTITY_ID)
	var dist := npc.position.distance_to(me.position) if me != null else 0.0
	var spec: Dictionary = Archetypes.TABLE[mind.archetype]
	var out := {
		"name": npc.display_name,
		"title": "%s%s" % [spec["label"], " (%s)" % npc.job if npc.job != &"" else ""],
		"stored": entity.has_component(ComponentNames.NPC_MIND),
		"tier": "%s, %d m away" % [tier(dist), roundi(dist)],
		"traits": _named(GanstoidEnums.MindTrait.keys(), NPCMind.traits(id, mind)),
		"drives": _named(GanstoidEnums.MindDrive.keys(), NPCMind.drives_now(id, mind, world.tick)),
		"mood": _named(GanstoidEnums.MindMood.keys(), NPCMind.mood_now(mind, world.tick)),
		"memories": memory_lines(world, mind),
		"about_you": about_you(world, id),
	}
	if with_links:
		out["links"] = links(world, npc, mind)
	if places != null:
		out["choices"] = choices(world, npc, mind, places)
	return out

## What they would do with free time now: the top few with their score and
## why, the one they would pick marked "<- picks".
static func choices(world: World, npc: NPCData, mind: NPCMindData, places: ActivityPlaces) -> Array:
	var scored := ActivityChooser.score_all(npc, mind, world.tick, places.for_person(world, npc, mind))
	var picked := ActivityChooser.pick(scored, npc.id, SimClock.day_number(world.tick), 0)
	var out := []
	for s in scored.slice(0, CHOICES_SHOWN):
		var mark := "  <- picks" if s["id"] == picked else ""
		out.append("%s %.2f: %s%s" % [Activities.TABLE[s["id"]]["label"], s["score"], s["why"], mark])
	return out

## An enum key in plain words: "WAS_ROBBED" -> "Was robbed".
static func words(key: String) -> String:
	var s := key.to_lower().replace("_", " ")
	return s.left(1).to_upper() + s.substr(1)

## [[name, value], ...] from enum keys.
static func _named(keys: Array, values: PackedFloat32Array) -> Array:
	var out := []
	for i in keys.size():
		out.append([words(keys[i]), values[i]])
	return out

## What they remember, newest first: "Was robbed: you, 3 h ago (90%)".
static func memory_lines(world: World, mind: NPCMindData) -> Array:
	var order := range(mind.mem_kind.size())
	order.sort_custom(func(a: int, b: int) -> bool: return mind.mem_tick[a] > mind.mem_tick[b])
	var out := []
	for i in order:
		var hours := float(world.tick - mind.mem_tick[i]) * 24.0 / float(SimClock.day_ticks)
		var kind := words(GanstoidEnums.MindMemory.keys()[mind.mem_kind[i]])
		out.append("%s: %s, %.0f h ago (%d%%)" % [kind, _who(world, StringName(mind.mem_who[i])), hours, roundi(mind.mem_weight[i] * 100.0)])
	return out

## [[label, text], ...]: household, workmates, gang, friends.
static func links(world: World, npc: NPCData, mind: NPCMindData) -> Array:
	var home := []
	var work := []
	for id in world.get_entities_with_component(ComponentNames.NPC):
		var other := _npc(world, id)
		if other == null or other.id == npc.id:
			continue
		if npc.home_building_id != &"" and other.home_building_id == npc.home_building_id:
			home.append(_who(world, other.id))   # the player shows as "you"
		if npc.work_building_id != &"" and other.work_building_id == npc.work_building_id:
			work.append(other.display_name)
	var friends := []
	for f in mind.friends:
		friends.append(_who(world, StringName(f)))
	return [["Lives with", _list(home)], ["Works with", _list(work)],
		["Gang", _gang(world, npc.gang_id)], ["Friends", _list(friends)]]

## What they think of you (ME1), in words.
static func about_you(world: World, id: StringName) -> String:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE) if player != null else null
	if state == null or not state.memories.has(id):
		return "never met you"
	var m: Dictionary = state.memories[id]
	return "%s (feeling %+.2f, %d times)" % [String(m.get("deed", "met")), float(m.get("feel", 0.0)), int(m.get("n", 0))]

static func _list(names: Array) -> String:
	if names.is_empty():
		return "nobody"
	var shown := ", ".join(names.slice(0, LINKS_SHOWN))
	return shown + (" and %d more" % (names.size() - LINKS_SHOWN) if names.size() > LINKS_SHOWN else "")

static func _gang(world: World, gang_id: StringName) -> String:
	if gang_id == &"":
		return "none"
	var gang_entity: Entity = world.entities.get(gang_id)
	var gang: GangData = gang_entity.get_component(ComponentNames.GANG) if gang_entity != null else null
	return gang.display_name if gang != null else String(gang_id)

static func _who(world: World, id: StringName) -> String:
	if id == &"":
		return "nobody"
	if id == PlayerFactory.PLAYER_ENTITY_ID:
		return "you"
	var npc := _npc(world, id)
	return npc.display_name if npc != null else String(id)

static func _npc(world: World, id: StringName) -> NPCData:
	var entity: Entity = world.entities.get(id)
	return entity.get_component(ComponentNames.NPC) if entity != null else null
