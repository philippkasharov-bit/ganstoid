## MG1b: the one place game time is defined. 60 sim ticks = 1 real second, and
## 1 game day = 1 real hour (Project Zomboid's default pacing), so a game day is
## 216,000 ticks. Checks that need to run many days may shorten day_ticks for
## the duration of the check (a fast clock); the game itself never does.
class_name SimClock
extends RefCounted

const TICKS_PER_SECOND := 60
const REAL_SECONDS_PER_GAME_DAY := 3600
const DEFAULT_DAY_TICKS := TICKS_PER_SECOND * REAL_SECONDS_PER_GAME_DAY

static var day_ticks: int = DEFAULT_DAY_TICKS

## Ticks in `hours` game hours.
static func hours(game_hours: float) -> int:
	return int(round(day_ticks * game_hours / 24.0))

## Ticks in `seconds` REAL seconds (reaction times, dwell pauses, timeouts).
static func real_seconds(seconds: float) -> int:
	return int(round(seconds * TICKS_PER_SECOND))

## 0.0 = midnight, 0.5 = noon.
static func day_fraction(tick: int) -> float:
	return float(posmod(tick, day_ticks)) / float(day_ticks)
