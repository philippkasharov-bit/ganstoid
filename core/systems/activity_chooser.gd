## NB2b: how a person chooses what to do with free time (utility scoring).
## Every activity they could do now gets a score, the product of:
##   need      how much it fills what they lack right now (hungry -> eat)
##   character how well it suits their traits (sociable -> night out)
##   distance  nearer places score higher
##   cost      can they afford it, and do they mind paying
##   dark      paranoid people avoid the street at night
##   habit     a small bonus for what they did last time at this time of day
##   appeal    the activity's own weight (data), which sets the overall mix
## Then one of the top few is picked, weighted by score and seeded from
## (person, day, wake), so people are sensible but not mechanical.
## Pure functions: no World writes, no shared random stream. Nothing in play
## calls this until NB2c; the F11 People tab shows it.
class_name ActivityChooser
extends RefCounted

const BASE_NEED := 0.15      # an activity is still worth something when no need is pressing
const NEED_CURVE := 1.5      # urgency = (1 - need) ^ this: a need matters more the lower it gets
const TRAIT_WEIGHT := 1.0    # how strongly character bends the scores
const TRAIT_FLOOR := 0.1
const FREE_WALK_M := 100.0   # a walk this short costs nothing
const DIST_HALF_M := 300.0   # this far past the free walk scores half as well
const PRICEY_BELOW := 0.85   # the cost cuts the score below this: "pricey"
const BROKE_SCORE := 0.2     # can't afford it: this much of the score is left
const STINGY := 0.5          # how much a fully greedy person minds paying $100
const DARK_FROM := 21.0
const DARK_UNTIL := 6.0
const HABIT_BONUS := 1.25
const PICK_TOP := 3          # the pick is among this many best
const SALT_PICK := 9400

const NEED_WORDS := ["tired", "hungry", "broke", "lonely", "uneasy", "bored"]   # per MindDrive

## [{id, score, why}] for every activity possible now, best first.
## `places`: ActivityPlaces.for_person; `habit`: what they did yesterday now.
static func score_all(npc: NPCData, mind: NPCMindData, tick: int, places: Dictionary, habit: StringName = &"") -> Array:
	var traits := NPCMind.traits(npc.id, mind)
	var drives := NPCMind.drives_now(npc.id, mind, tick)
	var hour := SimClock.day_fraction(tick) * 24.0
	var out := []
	for id in Activities.TABLE:
		if not places.has(id) or not Activities.is_open(id, hour):
			continue
		var s := score(id, traits, drives, hour, float(places[id][0]), npc.cash, id == habit)
		if s[0] > 0.0:
			out.append({"id": id, "score": s[0], "why": s[1]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"] or (a["score"] == b["score"] and String(a["id"]) < String(b["id"])))
	return out

## [score, why] for one activity.
static func score(id: StringName, traits: PackedFloat32Array, drives: PackedFloat32Array, hour: float, dist_m: float, cash: int, habit: bool) -> Array:
	var a: Dictionary = Activities.TABLE[id]
	var need := _need(a["fills"], drives)
	var fit := _fit(a["likes"], traits)
	var near := 1.0 / (1.0 + maxf(0.0, dist_m - FREE_WALK_M) / DIST_HALF_M)
	var cost := _cost(int(a["cost"]), cash, traits[GanstoidEnums.MindTrait.GREEDY])
	var dark := 1.0
	if a["walk"] in ["stroll", "linger"] and (hour >= DARK_FROM or hour < DARK_UNTIL):
		dark = clampf(1.2 - traits[GanstoidEnums.MindTrait.PARANOID], 0.1, 1.0)
	var total := float(a["appeal"]) * need * fit * near * cost * dark * (HABIT_BONUS if habit else 1.0)
	return [total, _why(a, drives, traits, dist_m, cost, habit)]

static func _need(fills: Dictionary, drives: PackedFloat32Array) -> float:
	var sum := BASE_NEED
	for k in fills:
		var urgency := pow(1.0 - drives[k], NEED_CURVE)
		sum += float(fills[k]) * (urgency if fills[k] > 0.0 else 1.0 - drives[k])
	return maxf(0.0, sum)

static func _fit(likes: Dictionary, traits: PackedFloat32Array) -> float:
	var f := 1.0
	for k in likes:
		f += float(likes[k]) * (traits[k] - 0.5) * 2.0 * TRAIT_WEIGHT
	return maxf(TRAIT_FLOOR, f)

static func _cost(price: int, cash: int, greedy: float) -> float:
	if price <= 0:
		return 1.0
	if cash < price:
		return BROKE_SCORE
	return clampf(1.0 - greedy * STINGY * float(price) / 100.0, BROKE_SCORE, 1.0)

## A few plain words on why: "hungry, sociable, 140 m".
static func _why(a: Dictionary, drives: PackedFloat32Array, traits: PackedFloat32Array, dist_m: float, cost: float, habit: bool) -> String:
	var words := []
	var top_need := -1
	for k in a["fills"]:
		if a["fills"][k] > 0.0 and drives[k] < 0.6 and (top_need < 0 or drives[k] < drives[top_need]):
			top_need = k
	if top_need >= 0:
		words.append(NEED_WORDS[top_need])
	var trait_word := _trait_word(a["likes"], traits)
	if trait_word != "":
		words.append(trait_word)
	if dist_m > 0.0:
		words.append("%d m" % roundi(dist_m))
	if cost < PRICEY_BELOW:
		words.append("pricey")
	if habit:
		words.append("habit")
	return ", ".join(words) if not words.is_empty() else "nothing better to do"

## The trait that pulls hardest towards this activity: "sociable", or
## "not paranoid" when a trait it dislikes is low. "" if none pulls much.
static func _trait_word(likes: Dictionary, traits: PackedFloat32Array) -> String:
	var best := -1
	var best_pull := 0.05
	for k in likes:
		var pull: float = likes[k] * (traits[k] - 0.5)
		if pull > best_pull:
			best = k
			best_pull = pull
	if best < 0:
		return ""
	var name := String(GanstoidEnums.MindTrait.keys()[best]).to_lower()
	return name if likes[best] > 0.0 else "not " + name

## One of the PICK_TOP best, weighted by score, the same for the same
## (person, day, wake). &"" if nothing was possible.
static func pick(scored: Array, npc_id: StringName, day: int, wake: int) -> StringName:
	var top := scored.slice(0, PICK_TOP)
	var total := 0.0
	for s in top:
		total += s["score"]
	if total <= 0.0:
		return &""
	var roll := float(absi(hash([npc_id, day, wake, SALT_PICK])) % 10007) / 10007.0 * total
	for s in top:
		roll -= s["score"]
		if roll < 0.0:
			return s["id"]
	return top[-1]["id"]
