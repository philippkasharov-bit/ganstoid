## UIF3: shapes the E menu like Zomboid's right-click menu. Every option gets a
## category (Shop & deals, Talk, Crime, Crew, Property, Car) and, where one
## helps, a short note on the right (crew size when recruiting). With more
## than a few options the menu opens on the categories and each one opens
## its own list.
class_name ActionMenuModel
extends RefCounted

const FLAT_UP_TO := 6   # this many options or fewer: one flat list, no categories
const ORDER := ["Shop & deals", "Talk", "Crime", "Crew", "Property", "Car"]

## Category for an option label (the labels are the game's own wording).
static func category(label: String) -> String:
	var l := label.to_lower()
	for pair in [["crew", "Crew"], ["recruit", "Crew"], ["talk", "Talk"], ["threaten", "Talk"], ["pay them", "Talk"],
			["bribe", "Talk"], ["lawyer", "Talk"], ["mug", "Crime"], ["pickpocket", "Crime"], ["rob ", "Crime"],
			["break in", "Crime"], ["pick the lock", "Crime"], ["kick the door", "Crime"], ["smash a window", "Crime"], ["go in", "Crime"],
			["board up", "Property"], ["carjack", "Crime"], ["spray", "Crime"], ["gang job", "Crime"], ["get in the car", "Car"],
			["property", "Property"], ["product", "Property"], ["makes", "Property"]]:
		if l.contains(pair[0]):
			return pair[1]
	return "Shop & deals"

## The note shown on the right of an option. (Who can see you lives in its
## own HUD piece, the eye; the menu stays about the actions.)
static func note(_world: World, _at: Vector2, label: String, state: PlayerStateData) -> String:
	if label.begins_with("Recruit"):
		return "crew %d/%d" % [state.crew_ids.size(), CrewSystem.MAX_CREW]
	return ""

## UIF4: civilians who could see a crime at `at` now and would call it in
## (shown by the eye in the HUD, DetectionEye)
## (the same rule CrimeSystem uses: in light range, no wall between).
static func eyes_on(world: World, at: Vector2) -> int:
	var n := 0
	for id in world.spatial_index.query_nearby(at):
		var e: Entity = world.entities.get(id)
		if e == null or e.has_component(ComponentNames.PLAYER_STATE):
			continue
		var npc: NPCData = e.get_component(ComponentNames.NPC)
		if npc == null or npc.is_crew or npc.is_down or npc.is_dealer or npc.gang_id != &"":
			continue
		if CrimeSystem.can_see(world, npc.position, at):
			n += 1
	return n

## Options grouped: category -> Array of [label, callable], in ORDER.
static func group(options: Array) -> Dictionary:
	var out := {}
	for c in ORDER:
		for o in options:
			if category(o[0]) == c:
				if not out.has(c):
					out[c] = []
				out[c].append(o)
	return out
