## QL3: quality in words, the way the street says it (1990s), not stars.
## Every drug has five grades by its 1-5 quality; workers and night spots
## have theirs too. Plus what a weed strain or a pill does, and where it
## sells best (StrainFit): a body high moves on poor corners, a head high
## or a smooth one on rich blocks and in clubs.
class_name Grades
extends RefCounted

const DRUGS := {
	&"weed": ["Schwag", "Mids", "Dank", "Kind bud", "Chronic"],
	&"pills": ["Bunk", "Weak", "Clean", "Strong", "Double-stacked"],
	&"meth": ["Garbage", "Dirty", "Clear", "Glass", "Pure glass"],
	&"coke": ["Baking soda", "Stepped-on", "Street", "Fishscale", "Uncut"],
	&"heroin": ["Garbage", "Cut", "Brown", "Tar", "China white"],
	&"fake_bill": ["Monopoly money", "Obvious", "Passable", "Good paper", "Superbill"],   # BZ5
}
const STAFF := ["Green", "Handy", "Solid", "Skilled", "A pro"]
const VENUE := ["Dive", "Decent", "Nice", "Hot spot", "The place to be"]
## Pills by the powder they're pressed from.
const PILLS := {
	&"pill_powder": {"name": "Doves", "base": 2.8, "high": "loved-up, dancing", "sells": "club"},
	&"speed_powder": {"name": "Speedy whites", "base": 2.0, "high": "wired, up all night", "sells": "poor"},
}
const FIT_BONUS := 1.25   # a strain or pill sold where it fits

static func step(q: float) -> int:
	return clampi(roundi(q), 1, 5)

## "Chronic" for 4.6 weed.
static func drug(good: StringName, q: float) -> String:
	var names: Array = DRUGS.get(good, DRUGS[&"weed"])
	return names[step(q) - 1]

## "Chronic (4.6)": the word, and the number for those who want it.
static func drug_text(good: StringName, q: float) -> String:
	return "%s (%.1f)" % [drug(good, q), q]

static func staff(skill: float) -> String:
	return STAFF[clampi(roundi(skill * 4.0), 0, 4)]

static func venue(stars: int) -> String:
	return VENUE[clampi(stars, 1, 5) - 1]

## Where the street pays most for what you carry: "poor", "rich", "club" or "".
static func sells_at(state: PlayerStateData, good: StringName) -> String:
	if good == &"weed":
		var sid := StringName(state.product.get("strain", ""))
		return String(GrowSystem.STRAINS.get(sid, {}).get("sells", ""))
	if good == &"pills":
		var kind := StringName(state.products.get("pills_kind", ""))
		return String(PILLS.get(kind, {}).get("sells", ""))
	return ""

## The bonus for selling here: on a block of this wealth, or in a club.
static func fit(state: PlayerStateData, good: StringName, wealth: float, in_club: bool) -> float:
	match sells_at(state, good):
		"club":
			return FIT_BONUS if in_club or wealth >= 0.6 else 1.0
		"rich":
			return FIT_BONUS if wealth >= 0.6 else 1.0
		"poor":
			return FIT_BONUS if wealth < 0.35 and not in_club else 1.0
	return 1.0

## One line about what you carry: "OG Kush · heavy body high · sells on poor corners".
static func about(state: PlayerStateData, good: StringName) -> String:
	var spec: Dictionary = {}
	if good == &"weed":
		spec = GrowSystem.STRAINS.get(StringName(state.product.get("strain", "")), {})
	elif good == &"pills":
		spec = PILLS.get(StringName(state.products.get("pills_kind", "")), {})
	if spec.is_empty():
		return ""
	var where: String = {"poor": "sells best on poor corners", "rich": "rich buyers pay more", "club": "sells best in clubs"}.get(spec.get("sells", ""), "")
	return "%s · %s%s" % [spec["name"], spec["high"], " · " + where if where != "" else ""]
