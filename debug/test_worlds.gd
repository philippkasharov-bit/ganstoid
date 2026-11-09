## Shared setup for the headless checks: a new game on the real city (MG1),
## with a FAST clock (1 game day = 1800 ticks = 30 s) so day-based rules can be
## checked in seconds. Movement is straight-line unless a check installs SimNav.
class_name TestWorlds
extends RefCounted

const FAST_DAY_TICKS := 1800
const DISTRICT_RADIUS := 900.0
const POPULATION := 130

static var _city: CityData = null

static func city() -> CityData:
	if _city == null:
		_city = CityData.load_file()
	return _city

static func real_city(world: World, seed: int = 1) -> void:
	SimClock.day_ticks = FAST_DAY_TICKS
	WorldGenerator.generate_real_city_game(world, seed, city(), city().spawn, DISTRICT_RADIUS, POPULATION)
