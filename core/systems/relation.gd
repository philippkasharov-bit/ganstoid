## UI7: who someone is to you, at a glance (Phil: "friend, enemy or a
## complete stranger?"). Read-only. A colour for the ring at their feet and
## a short label for their name card; strangers get nothing.
class_name Relation
extends RefCounted

const CREW := Color("4a8fe7")
const STAFF := Color("39b5b5")
const POLICE := Color("2f4f9e")
const FRIEND := Color("5cc46a")
const SCARED := Color("e8c440")
const ENEMY := Color("e04a40")
const WARY := Color("e6913a")
const TRADE := Color("a26ae0")
const DEED_WORDS := {"robbed": "you robbed them", "hurt": "you hurt them", "threatened": "you threatened them",
	"caught_lifting": "caught your hand in their pocket", "saw_crime": "saw you do a crime", "bad_batch": "you sold them trash",
	"store_robbed": "you robbed their store"}

## [colour, label] for someone, or [] for a stranger.
static func of(world: World, state: PlayerStateData, n: NPCData) -> Array:
	if n.is_crew:
		return [CREW, "Your crew"]
	if state.staff.has(n.id):
		return [STAFF, "Works for you"]
	if n.is_cop:
		return [POLICE, "Police"]
	if n.gang_id != &"":
		if state.gang_member == n.gang_id:
			return [CREW, "Your set"]
		var standing: float = state.gang_standing.get(n.gang_id, 0.5)
		var name := GangLifeSystem.gang_name(world, n.gang_id)
		if standing < ReactionSystem.DISLIKED:
			return [ENEMY, "%s: they want you gone" % name]
		return [FRIEND if standing >= ReactionSystem.FRIENDLY else WARY, "%s%s" % [name, ": friendly" if standing >= ReactionSystem.FRIENDLY else ""]]
	if n.is_dealer:
		return [TRADE, "Dealer"]
	if n.is_fixer and state.known.has(n.id):
		return [TRADE, "Fixer"]
	var m: Variant = state.memories.get(n.id)
	if not m is Dictionary:
		return []
	var feel := float(m.get("feel", 0.0))
	var deed := String(m.get("deed", ""))
	if n.fear >= CourtSystem.SCARED_AT and feel < 0.0:
		return [SCARED, "Scared of you"]
	if feel >= 0.25:
		return [FRIEND, "Regular customer" if deed == "good_product" else "Friend"]
	if feel <= MemorySystem.RUN_AT:
		return [ENEMY, "Enemy: " + DEED_WORDS.get(deed, "they hate you")]
	if feel < 0.0:
		return [WARY, "Knows your face: " + DEED_WORDS.get(deed, "")]
	return []
