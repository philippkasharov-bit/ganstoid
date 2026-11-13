## HP1/HP2: Project Zomboid's body model for the player: 17 parts (head, neck,
## upper and lower torso, groin, and per side upper arm, forearm, hand,
## thigh, shin, foot). Each hit lands on one part and leaves Zomboid's kind of
## wound for what did it:
##   fists           bruise
##   bat             bruise; a hard hit on an arm or leg bone: fracture
##   knife           laceration; a deep stab: deep wound
##   bullet          bullet wound (deep, bleeds hard)
## Lacerations, deep and bullet wounds bleed until bandaged. A bandage goes on
## the worst bleeding wound first; a bandage left on a day gets dirty, and a
## dirty or missing bandage on an open wound can turn it infected (it stops
## healing and slowly drains health until the bandage is changed). Parts heal
## while you are fed and not bleeding; fractures slowest. Hurt legs and feet
## slow you; hurt arms and hands spoil your aim. NPCData.health stays the
## number of record; this is where it hurts and how.
class_name BodyParts
extends RefCounted

const PARTS := ["head", "neck", "torso_upper", "torso_lower", "groin",
	"r_upper_arm", "r_forearm", "r_hand", "l_upper_arm", "l_forearm", "l_hand",
	"r_thigh", "r_shin", "r_foot", "l_thigh", "l_shin", "l_foot"]
const NAMES := {"head": "Head", "neck": "Neck", "torso_upper": "Upper torso", "torso_lower": "Lower torso", "groin": "Groin",
	"r_upper_arm": "Right upper arm", "r_forearm": "Right forearm", "r_hand": "Right hand",
	"l_upper_arm": "Left upper arm", "l_forearm": "Left forearm", "l_hand": "Left hand",
	"r_thigh": "Right thigh", "r_shin": "Right shin", "r_foot": "Right foot",
	"l_thigh": "Left thigh", "l_shin": "Left shin", "l_foot": "Left foot"}
const HIT_WEIGHT := {"head": 6, "neck": 2, "torso_upper": 16, "torso_lower": 14, "groin": 4,
	"r_upper_arm": 6, "r_forearm": 6, "r_hand": 3, "l_upper_arm": 6, "l_forearm": 6, "l_hand": 3,
	"r_thigh": 7, "r_shin": 5, "r_foot": 2, "l_thigh": 7, "l_shin": 5, "l_foot": 2}
const BONES := ["r_upper_arm", "r_forearm", "l_upper_arm", "l_forearm", "r_thigh", "r_shin", "l_thigh", "l_shin"]
const LEGS := ["r_thigh", "r_shin", "r_foot", "l_thigh", "l_shin", "l_foot"]
const ARMS := ["r_upper_arm", "r_forearm", "r_hand", "l_upper_arm", "l_forearm", "l_hand"]

## Wound kinds, mildest first, with how bad each is (0..3) and whether it bleeds.
const WOUNDS := {"": [0, false], "bruise": [1, false], "laceration": [2, true], "deep wound": [3, true],
	"bullet wound": [3, true], "fracture": [3, false]}
const PART_DAMAGE := 2.2          # a part takes more of a hit than the whole body does
const FRACTURE_AT := 0.3          # a blunt hit leaving a limb bone under this breaks it
const DEEP_AT := 0.18             # a blade hit this hard goes deep
const HEAL_PER_DAY := 0.6
const DIRTY_AFTER_DAYS := 1.0     # a bandage needs changing after a day
const INFECT_PER_DAY := 0.5       # chance-free: an open wound with no clean bandage festers at this rate
const INFECTED_DRAIN_PER_DAY := 0.15

## Fills in any missing part and drops parts from an older save's model.
static func ensure(state: PlayerStateData) -> void:
	for p in state.body.keys():
		if not NAMES.has(p):
			state.body.erase(p)
	for p in PARTS:
		if not state.body.has(p):
			state.body[p] = fresh()

static func fresh() -> Dictionary:
	return {"hp": 1.0, "wound": "", "bleeding": false, "bandaged": false, "bandage_age": 0.0, "infection": 0.0}

## A hit on the player: picks the part, opens the wound. Returns the part hit.
static func hit(world: World, state: PlayerStateData, w: Dictionary) -> String:
	ensure(state)
	var part := _pick(world.runtime_rng)
	var b: Dictionary = state.body[part]
	b["hp"] = maxf(0.0, float(b["hp"]) - float(w["damage"]) * PART_DAMAGE)
	b["bandaged"] = false
	var wound := _wound_for(part, b, w)
	if WOUNDS[wound][0] >= WOUNDS[b["wound"]][0]:
		b["wound"] = wound   # a worse wound replaces a milder one
	b["bleeding"] = b["bleeding"] or WOUNDS[wound][1]
	return part

static func _wound_for(part: String, b: Dictionary, w: Dictionary) -> String:
	if w.get("blunt", false):
		return "fracture" if BONES.has(part) and float(b["hp"]) < FRACTURE_AT else "bruise"
	if w.has("spread_hip_deg"):
		return "bullet wound"
	return "deep wound" if float(w["damage"]) >= DEEP_AT else "laceration"

static func _pick(rng: RandomNumberGenerator) -> String:
	var roll := rng.randi_range(1, 100)
	for p in PARTS:
		roll -= HIT_WEIGHT[p]
		if roll <= 0:
			return p
	return "torso_upper"

## 0 fine .. 3 severe: the wound's weight, plus a notch for bleeding, infection or very low condition.
static func severity(b: Dictionary) -> int:
	var s: int = WOUNDS.get(b["wound"], [0, false])[0]
	if b["bleeding"] or float(b.get("infection", 0.0)) >= 1.0 or float(b["hp"]) < 0.3:
		s += 1
	if s == 0 and float(b["hp"]) < 0.95:
		s = 1
	return mini(s, 3)

## Bandages the worst wound that needs one (bleeding first). True if one was done.
static func bandage(state: PlayerStateData, npc: NPCData) -> bool:
	ensure(state)
	var best := ""
	for p in PARTS:
		var b: Dictionary = state.body[p]
		var needs: bool = WOUNDS[b["wound"]][1] and (not b["bandaged"] or _dirty(b))
		if needs and (best == "" or _worse(b, state.body[best])):
			best = p
	if best != "":
		var b: Dictionary = state.body[best]
		b["bleeding"] = false
		b["bandaged"] = true
		b["bandage_age"] = 0.0
		b["infection"] = minf(float(b["infection"]), 0.99)   # a clean dressing stops it getting worse
	npc.bleeding = is_bleeding(state)
	return best != ""

static func _dirty(b: Dictionary) -> bool:
	return b["bandaged"] and float(b["bandage_age"]) >= DIRTY_AFTER_DAYS

static func dirty(b: Dictionary) -> bool:
	return _dirty(b)

static func _worse(a: Dictionary, b: Dictionary) -> bool:
	if a["bleeding"] != b["bleeding"]:
		return a["bleeding"]
	return severity(a) > severity(b)

static func is_bleeding(state: PlayerStateData) -> bool:
	for p in state.body:
		if state.body[p]["bleeding"]:
			return true
	return false

## Time passing: healing, bandages getting dirty, open wounds festering.
## Returns health lost to infection.
static func heal(state: PlayerStateData, days: float) -> float:
	var drain := 0.0
	for p in state.body:
		var b: Dictionary = state.body[p]
		if b["bandaged"]:
			b["bandage_age"] = float(b["bandage_age"]) + days
		var open: bool = WOUNDS[b["wound"]][1] and (not b["bandaged"] or _dirty(b))
		if open:
			b["infection"] = minf(1.0, float(b["infection"]) + INFECT_PER_DAY * days)
		if float(b["infection"]) >= 1.0:
			drain += INFECTED_DRAIN_PER_DAY * days
			continue   # an infected wound does not heal
		if b["bleeding"]:
			continue
		var rate := HEAL_PER_DAY * (0.3 if b["wound"] == "fracture" else (1.5 if b["bandaged"] and not _dirty(b) else 1.0))
		b["hp"] = minf(1.0, float(b["hp"]) + rate * days)
		if b["hp"] >= 0.95:
			state.body[p] = fresh()
	return drain

## Movement speed from the legs and feet (a broken leg is a limp).
static func move_mult(state: PlayerStateData) -> float:
	return _limb_mult(state, LEGS)

## Aim spread from arms and hands (more spread when they hurt).
static func aim_mult(state: PlayerStateData) -> float:
	return 1.0 / _limb_mult(state, ARMS)

static func _limb_mult(state: PlayerStateData, parts: Array) -> float:
	var worst := 1.0
	for p in parts:
		if state.body.has(p):
			var b: Dictionary = state.body[p]
			worst = minf(worst, 0.35 if b["wound"] == "fracture" else 0.55 + 0.45 * float(b["hp"]))
	return worst
