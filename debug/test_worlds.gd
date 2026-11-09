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

## AR0 (Godot 4.7): navmeshes sync in the background. Await this before querying
## them; returns false if they are not ready within `timeout_s`.
static func wait_nav(tree: SceneTree, navs: Array, timeout_s: float = 120.0) -> bool:
	var start := Time.get_ticks_msec()
	while navs.any(func(n: Variant) -> bool: return not n.is_ready()):
		if Time.get_ticks_msec() - start > timeout_s * 1000.0:
			return false
		await tree.process_frame
	return true
