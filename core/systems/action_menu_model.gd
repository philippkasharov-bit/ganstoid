## UIF3: shapes the E menu like Zomboid's right-click menu. Every option gets a
## category (Shop & deals, Talk, Crime, Crew, Property, Car) and a short note
## on the right: what it costs, or for crimes how many people could see it
## ("3 watching" / "unseen"), since only witnesses bring the law. With more
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
			["break in", "Crime"], ["carjack", "Crime"], ["spray", "Crime"], ["gang job", "Crime"], ["get in the car", "Car"],
			["property", "Property"], ["product", "Property"], ["makes", "Property"]]:
		if l.contains(pair[0]):
			return pair[1]
	return "Shop & deals"

## The note shown on the right of an option.
static func note(world: World, at: Vector2, label: String, state: PlayerStateData) -> String:
	var cat := category(label)
	if cat == "Crime":
		var eyes := eyes_on(world, at)
		return "unseen" if eyes == 0 else "%d watching" % eyes
	if label.begins_with("Recruit"):
		return "crew %d/%d" % [state.crew_ids.size(), CrewSystem.MAX_CREW]
	return ""

## Civilians who could see a crime at `at` now and would call it in
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
