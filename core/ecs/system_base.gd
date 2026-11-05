## Base class every sim system extends. A system declares its tick_rate and
## implements process_entities — World calls it at the right cadence, the
## system never schedules itself.
class_name SystemBase
extends RefCounted

var tick_rate: GanstoidEnums.TickRate = GanstoidEnums.TickRate.WARM

## Optional component filter (ComponentNames.*). Empty (&"") = no filter,
## World passes every entity (old behavior, still default). Set this when a
## system only ever reads one component type — World then hands it a
## pre-indexed subset instead of every entity in the sim, so an NPC-only
## system stops paying O(all buildings + gangs + ...) per tick at city scale.
var required_component: StringName = &""

## entities: Dictionary[StringName, Entity] — already filtered to
## required_component if this system declared one. READ-ONLY: this is a
## live reference into World's own entity dict/index, not a copy -- add or
## remove entities via World.register_entity/unregister_entity, never by
## mutating this dict directly. delta is wall/sim time since last call of
## THIS system (not necessarily last frame — warm/cold systems skip
## frames). tick is the World's monotonic tick counter.
func process_entities(_entities: Dictionary, _delta: float, _tick: int) -> void:
	push_error("SystemBase.process_entities not overridden by %s" % get_script().get_global_name())
