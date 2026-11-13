## Traits and fame (T1 + F1). You earn traits by what you keep doing; every
## trait has an upside and a downside, and a gold tier for doing it a lot.
## Earned traits stay (permadeath run). Fame (0-100) rises with every crime
## someone sees and with rank-ups, fades slowly; the more famous you are,
## the more easily witnesses place your face.
class_name Traits
extends RefCounted

## id: [deed counted, normal at, gold at, name, upside, downside]
const LIST := {
	&"killer":   [&"kills", 3, 15, "Killer", "threats always land; nobody bolts when mugged", "bribes cost 50% more"],
	&"brawler":  [&"knockouts", 8, 30, "Brawler", "melee +20%", "aim 15% shakier (hothead)"],
	&"ghost":    [&"unseen", 10, 40, "Ghost", "witnesses place you half as often", "deals pay 10% less (no name on the street)"],
	&"talker":   [&"talks", 15, 50, "Smooth talker", "pay-offs and bribes 30% cheaper", "threats only half as scary"],
	&"wheelman": [&"cars", 5, 20, "Wheelman", "hotwires 40% faster", "car thefts are noticed more"],
	&"dealer":   [&"deals", 30, 120, "Plug", "deals pay 10% more", "witnessed deals weigh more in your case"],
}
const GOLD_BONUS := 1.5            # a gold trait's upside is half again as strong
const FAME_PER_SEVERITY := 5.0
const FAME_FADE_PER_HOUR := 0.5

## Counts a deed; earns or upgrades the trait it feeds. Returns the trait id earned now, or &"".
static func deed(world: World, state: PlayerStateData, kind: StringName) -> StringName:
	state.deeds[kind] = state.deeds.get(kind, 0) + 1
	for id in LIST:
		var t: Array = LIST[id]
		if t[0] != kind:
			continue
		var n: int = state.deeds[kind]
		var tier: int = state.traits.get(id, 0)
		var want := 2 if n >= t[2] else (1 if n >= t[1] else 0)
		if want > tier:
			state.traits[id] = want
			state.last_message = "%s%s: %s. But %s." % ["GOLD " if want == 2 else "", t[3], t[4], t[5]]
			state.message_alert = true
			state.message_serial += 1
			return id
	return &""

static func has(state: PlayerStateData, id: StringName) -> bool:
	return state.traits.get(id, 0) > 0

## 1.0 without the trait, the upside with it (stronger at gold).
static func edge(state: PlayerStateData, id: StringName, upside: float) -> float:
	var tier: int = state.traits.get(id, 0)
	if tier == 0:
		return 1.0
	return 1.0 + (upside - 1.0) * (GOLD_BONUS if tier == 2 else 1.0)

static func summary(state: PlayerStateData) -> String:
	var parts: PackedStringArray = []
	for id in state.traits:
		parts.append(("★ " if state.traits[id] == 2 else "") + String(LIST[id][3]))
	return ", ".join(parts) if not parts.is_empty() else "none yet"
