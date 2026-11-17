## RP1: street reputation, read from fame (0-100: grows when people see what
## you do and talk about it, fades when you lie low). Five tiers, each with
## real effects, so being known is worth its risk (being recognised more):
##   Known       muggings: fewer victims dare to run
##   Respected   + recruits say yes more often; corner boys let you walk by
##   Feared      + hustles pay more; even fewer victims run
##   Legend      + the most of all of it
## add() is how anything big (a hustle, a rival down, a corner held) raises it.
class_name Rep
extends RefCounted

const TIERS := ["Nobody", "Known", "Respected", "Feared", "Legend"]
const AT := [0.0, 10.0, 30.0, 60.0, 85.0]
const BRAVE_CUT := [1.0, 0.75, 0.6, 0.35, 0.2]        # x the share of victims who run
const RECRUIT_BONUS := [0.0, 0.0, 0.12, 0.2, 0.3]
const HUSTLE_PAY := [1.0, 1.0, 1.1, 1.25, 1.4]
const GANG_LETS_PASS := 2                              # this tier and up: no corner warnings

static func tier(state: PlayerStateData) -> int:
	var t := 0
	for i in AT.size():
		if state.fame >= AT[i]:
			t = i
	return t

static func name_of(state: PlayerStateData) -> String:
	return TIERS[tier(state)]

## Raise it; a new tier gets a stamp.
static func add(state: PlayerStateData, by: float) -> void:
	var before := tier(state)
	state.fame = clampf(state.fame + by, 0.0, 100.0)
	if tier(state) > before:
		StampView.put(state, TIERS[tier(state)].to_upper(), "your name means something now")
