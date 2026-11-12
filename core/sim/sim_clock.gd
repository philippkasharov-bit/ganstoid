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

## T1: time is counted from the start of a life, not a real calendar (no real
## history to get wrong). 30-day months, 12-month years.
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12

## Day 1 is the first day.
static func day_number(tick: int) -> int:
	return int(tick / day_ticks) + 1

## "Year 1, Month 2" for the clock box.
static func year_month(tick: int) -> String:
	var months := int(tick / day_ticks) / DAYS_PER_MONTH
	return "Year %d, Month %d" % [months / MONTHS_PER_YEAR + 1, months % MONTHS_PER_YEAR + 1]

## "1 year, 3 months, 12 days" from a number of whole-or-part days lived.
static func lasted(days: float) -> String:
	var d := int(days)
	var years := d / (DAYS_PER_MONTH * MONTHS_PER_YEAR)
	var months := (d / DAYS_PER_MONTH) % MONTHS_PER_YEAR
	var rest := d % DAYS_PER_MONTH
	var parts: PackedStringArray = []
	for pair in [[years, "year"], [months, "month"], [rest, "day"]]:
		if pair[0] > 0:
			parts.append("%d %s%s" % [pair[0], pair[1], "" if pair[0] == 1 else "s"])
	if parts.is_empty():
		return "%d hours" % int(days * 24.0)
	return ", ".join(parts)
