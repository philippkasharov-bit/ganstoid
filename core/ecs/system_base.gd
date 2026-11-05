## Base class every sim system extends. A system declares its tick_rate and
## implements process_entities — World calls it at the right cadence, the
## system never schedules itself.
class_name SystemBase
extends RefCounted

var tick_rate: GanstoidEnums.TickRate = GanstoidEnums.TickRate.WARM

## entities: Dictionary[StringName, Entity]. delta is wall/sim time since last
## call of THIS system (not necessarily last frame — warm/cold systems skip
## frames). tick is the World's monotonic tick counter.
func process_entities(_entities: Dictionary, _delta: float, _tick: int) -> void:
	push_error("SystemBase.process_entities not overridden by %s" % get_script().get_global_name())
