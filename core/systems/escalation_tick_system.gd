## Criminal Record Ladder, Phase 1 slice only: CLEAN <-> WARNED (tier 1),
## the "first-offense warning" tier the roadmap calls for this phase.
## Higher tiers (REPEAT_OFFENDER and up) and the whole Beef Ladder track
## are Phase 4's job -- no rival gangs exist yet to generate beef, and
## repeat-offense tiers need a real jail/cooldown system behind them that
## doesn't exist yet either. Building those now would be guessing at specs
## Phase 4 hasn't locked.
##
## Two jobs: raise law_tier on a witnessed crime (event-driven, see
## on_crime_witnessed), and decay it back down if nothing else happens for
## a while (tick-driven, process_entities). CopAISystem handles the OTHER
## way tier 1 clears -- getting caught -- by resetting law_tier directly
## when it arrests the player; this system doesn't need to know that
## happened, it just won't see WARNED anymore next tick.
class_name EscalationTickSystem
extends SystemBase

## How long (in ticks) tier 1 heat lasts with no further triggers before it
## cools off on its own -- "the cops stopped actively looking for you."
const DECAY_DELAY_TICKS := 600  # ~10 sim-seconds at 60 tick/s

## WeakRef, not a direct World reference -- see NPCScheduleSystem's _world
## property doc for why (avoids a System<->World retain cycle).
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.WARM
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	for entity in entities.values():
		var state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
		if state.law_tier == GanstoidEnums.LawTier.WARNED and tick - state.law_tier_last_escalation_tick > DECAY_DELAY_TICKS:
			state.law_tier = GanstoidEnums.LawTier.CLEAN

## Subscribed directly to World.event_bus by SystemRegistry (this system's
## signature already matches EventBus.subscribe's Callable shape, so no
## wrapping lambda is needed the way a non-world-aware listener might).
func on_crime_witnessed(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.CRIME_WITNESSED:
		return
	var matches := _world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	for entity in matches.values():
		var state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
		if state.law_tier == GanstoidEnums.LawTier.CLEAN:
			state.law_tier = GanstoidEnums.LawTier.WARNED
		state.law_tier_last_escalation_tick = _world.tick
