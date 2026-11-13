## HP1: Zomboid-style body parts for the player. Every hit lands on one part
## (torso most often, head least) and leaves a wound by what did it: fists and
## bats bruise (a hard bat hit can break an arm or leg), knives cut, bullets
## leave a bullet wound. Cuts and bullet wounds bleed until bandaged; a
## bandage goes on the worst bleeding part first. Parts heal slowly while you
## are fed and not bleeding. Hurt legs slow you down; hurt arms and hands
## spoil your aim. Overall health (NPCData.health) stays the number of record;
## this is where it hurts and how.
class_name BodyParts
extends RefCounted

const PARTS := ["head", "torso", "l_arm", "r_arm", "l_hand", "r_hand", "l_leg", "r_leg"]
const NAMES := {"head": "Head", "torso": "Torso", "l_arm": "Left arm", "r_arm": "Right arm",
	"l_hand": "Left hand", "r_hand": "Right hand", "l_leg": "Left leg", "r_leg": "Right leg"}
const HIT_WEIGHT := {"head": 8, "torso": 34, "l_arm": 11, "r_arm": 11, "l_hand": 5, "r_hand": 5, "l_leg": 13, "r_leg": 13}
const PART_DAMAGE := 2.2          # a part takes more of a hit than the whole body does
const FRACTURE_AT := 0.3          # a blunt hit leaving an arm/leg under this breaks it
const HEAL_PER_DAY := 0.6

## Fills in any missing part (new life, or an older save).
static func ensure(state: PlayerStateData) -> void:
	for p in PARTS:
		if not state.body.has(p):
			state.body[p] = {"hp": 1.0, "wound": "", "bleeding": false, "bandaged": false}

## A hit on the player: picks the part, opens the wound. Returns the part hit.
static func hit(world: World, state: PlayerStateData, w: Dictionary) -> String:
	ensure(state)
	var part := _pick(world.runtime_rng)
	var b: Dictionary = state.body[part]
	b["hp"] = maxf(0.0, float(b["hp"]) - float(w["damage"]) * PART_DAMAGE)
	b["bandaged"] = false
	if w.get("blunt", false):
		var limb: bool = part.ends_with("arm") or part.ends_with("leg")
		b["wound"] = "fracture" if limb and b["hp"] < FRACTURE_AT else ("bruise" if b["wound"] == "" else b["wound"])
	else:
		b["wound"] = "bullet wound" if w.has("spread_hip_deg") else "cut"
		b["bleeding"] = true
	return part

static func _pick(rng: RandomNumberGenerator) -> String:
	var roll := rng.randi_range(1, 100)
	for p in PARTS:
		roll -= HIT_WEIGHT[p]
		if roll <= 0:
			return p
	return "torso"

## Bandages the worst bleeding part (else the most hurt open wound). True if one was done.
static func bandage(state: PlayerStateData, npc: NPCData) -> bool:
	ensure(state)
	var best := ""
	for p in PARTS:
		var b: Dictionary = state.body[p]
		if b["wound"] != "" and not b["bandaged"] and (best == "" or _worse(b, state.body[best])):
			best = p
	if best != "":
		state.body[best]["bleeding"] = false
		state.body[best]["bandaged"] = true
	npc.bleeding = is_bleeding(state)
	return best != ""

static func _worse(a: Dictionary, b: Dictionary) -> bool:
	if a["bleeding"] != b["bleeding"]:
		return a["bleeding"]
	return float(a["hp"]) < float(b["hp"])

static func is_bleeding(state: PlayerStateData) -> bool:
	for p in state.body:
		if state.body[p]["bleeding"]:
			return true
	return false

## Slow healing; a healed part loses its wound (a fracture takes longest).
static func heal(state: PlayerStateData, days: float) -> void:
	for p in state.body:
		var b: Dictionary = state.body[p]
		if b["bleeding"]:
			continue
		var rate := HEAL_PER_DAY * (0.3 if b["wound"] == "fracture" else (1.5 if b["bandaged"] else 1.0))
		b["hp"] = minf(1.0, float(b["hp"]) + rate * days)
		if b["hp"] >= 0.95:
			b["wound"] = ""
			b["bandaged"] = false

## Movement speed from the legs (a broken leg is a limp).
static func move_mult(state: PlayerStateData) -> float:
	return _limb_mult(state, ["l_leg", "r_leg"])

## Aim spread from arms and hands (more spread when they hurt).
static func aim_mult(state: PlayerStateData) -> float:
	return 1.0 / _limb_mult(state, ["l_arm", "r_arm", "l_hand", "r_hand"])

static func _limb_mult(state: PlayerStateData, parts: Array) -> float:
	var worst := 1.0
	for p in parts:
		if state.body.has(p):
			var b: Dictionary = state.body[p]
			worst = minf(worst, 0.35 if b["wound"] == "fracture" else 0.55 + 0.45 * float(b["hp"]))
	return worst
