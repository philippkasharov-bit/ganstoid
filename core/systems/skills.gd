## Skills (S1): you get better at what you do. Five skills, levels 0-10, XP
## from doing the thing. Each level is a small, honest edge (5%), never a
## different game: a level-10 shooter still misses at 30 m in the dark.
##   shooting  tighter spread           (XP: shots fired, hits)
##   melee     harder blows             (XP: blows that land)
##   theft     faster hotwires, surer pickpockets   (XP: each success)
##   driving   quicker off the line     (XP: distance driven)
##   hustle    better deal prices       (XP: each deal)
class_name Skills
extends RefCounted

const NAMES: Array[StringName] = [&"shooting", &"melee", &"theft", &"driving", &"hustle"]
const MAX_LEVEL := 10
const XP_PER_LEVEL_SQ := 25.0      # level n needs 25 * n^2 XP (10 needs 2500)
const EDGE_PER_LEVEL := 0.05
## SK2: Zomboid groups its skills under headings; ours, with what a level
## gives and how XP comes in (the Skills tab's hover card).
const GROUPS := [["Combat", [&"shooting", &"melee"]], ["Crime", [&"theft", &"hustle"]], ["Vehicles", [&"driving"]]]
const PER_LEVEL := {&"shooting": "tighter spread", &"melee": "harder blows", &"theft": "faster hotwires, surer pickpockets",
	&"driving": "quicker off the line", &"hustle": "better deal prices"}
const XP_FROM := {&"shooting": "Shots fired and hits", &"melee": "Blows that land", &"theft": "Each hotwire, lockpick or pickpocket",
	&"driving": "Distance driven", &"hustle": "Each deal"}

## [level, xp into this level, xp this level needs] (needs 0 at max).
static func progress(xp: float) -> Array:
	var lvl := mini(MAX_LEVEL, int(sqrt(xp / XP_PER_LEVEL_SQ)))
	if lvl >= MAX_LEVEL:
		return [MAX_LEVEL, 0.0, 0.0]
	var lo := XP_PER_LEVEL_SQ * lvl * lvl
	return [lvl, xp - lo, XP_PER_LEVEL_SQ * (lvl + 1) * (lvl + 1) - lo]

static func level(state: PlayerStateData, skill: StringName) -> int:
	var xp: float = state.skills.get(skill, 0.0)
	return mini(MAX_LEVEL, int(sqrt(xp / XP_PER_LEVEL_SQ)))

## Adds XP; returns the new level if this crossed one, else -1.
static func gain(state: PlayerStateData, skill: StringName, xp: float) -> int:
	var before := level(state, skill)
	state.skills[skill] = state.skills.get(skill, 0.0) + xp
	var after := level(state, skill)
	return after if after > before else -1

## Multiplier that shrinks with level (spread, hotwire time): 1.0 .. 0.5.
static func less(state: PlayerStateData, skill: StringName) -> float:
	return 1.0 - EDGE_PER_LEVEL * level(state, skill)

## Multiplier that grows with level (damage, acceleration, prices): 1.0 .. 1.5.
static func more(state: PlayerStateData, skill: StringName) -> float:
	return 1.0 + EDGE_PER_LEVEL * level(state, skill)

## One line for the bag panel.
static func summary(state: PlayerStateData) -> String:
	var parts: PackedStringArray = []
	for s in NAMES:
		parts.append("%s %d" % [String(s).capitalize(), level(state, s)])
	return "   ".join(parts)

## Gains XP and says so when a level is reached.
static func train(world: World, state: PlayerStateData, skill: StringName, xp: float) -> void:
	var up := gain(state, skill, xp * GameRules.xp(world))   # O1
	if up > 0:
		state.last_message = "%s %d" % [String(skill).capitalize(), up]   # A7: floats up in gold, Zomboid's "+Melee"
		state.message_tone = 2
		state.message_alert = false
		state.message_serial += 1
