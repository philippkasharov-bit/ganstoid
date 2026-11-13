## E2: runs the city's money day (EconomyFlow.run_day) once a game day, in the
## evening after the shops shut, on its own tick.
class_name EconomyFlowSystem
extends SystemBase

const AT_HOUR := 21.0

const NEVER := -1000000000
var _last_day := NEVER
var _world_ref: WeakRef

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = &""

func process_entities(_entities: Dictionary, _delta: float, tick: int) -> void:
	var day := floori(float(tick - SimClock.hours(AT_HOUR)) / SimClock.day_ticks)   # floor: before the first 21:00 is day -1, not 0
	if day == _last_day:
		return
	var first := _last_day == NEVER
	_last_day = day
	var w: World = _world_ref.get_ref()
	if w != null and not first:   # not on the first tick of a session: only when a day has really turned over
		EconomyFlow.run_day(w)
