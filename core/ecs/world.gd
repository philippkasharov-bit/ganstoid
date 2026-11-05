## Orchestrator: owns all entities, runs systems at their declared tick_rate.
## step() is called by a driver (Godot _physics_process, or a headless test
## loop) — World itself never touches the scene tree, keeping it testable
## and deterministic independent of frame rate.
class_name World
extends RefCounted

## Warm systems run once every N ticks rather than every tick — tunable per
## playtesting, not a magic number baked into call sites.
const WARM_TICK_INTERVAL := 10

var entities: Dictionary = {}       # StringName -> Entity
var _hot_systems: Array[SystemBase] = []
var _warm_systems: Array[SystemBase] = []
var _cold_systems: Dictionary = {}  # StringName -> SystemBase, invoked on-demand only

var tick: int = 0

func register_entity(entity: Entity) -> void:
	entities[entity.id] = entity

func unregister_entity(id: StringName) -> void:
	entities.erase(id)

## cold_name is required for COLD systems (lookup key for trigger_cold_system);
## ignored otherwise.
func register_system(system: SystemBase, cold_name: StringName = &"") -> void:
	match system.tick_rate:
		GanstoidEnums.TickRate.HOT:
			_hot_systems.append(system)
		GanstoidEnums.TickRate.WARM:
			_warm_systems.append(system)
		GanstoidEnums.TickRate.COLD:
			assert(cold_name != &"", "COLD system must be registered with a cold_name")
			_cold_systems[cold_name] = system

## Advances the sim by one tick. Hot systems always run; warm systems run
## only on the interval boundary, so their cost is amortized across frames.
func step(delta: float) -> void:
	tick += 1
	for system in _hot_systems:
		system.process_entities(entities, delta, tick)
	if tick % WARM_TICK_INTERVAL == 0:
		var warm_delta := delta * WARM_TICK_INTERVAL
		for system in _warm_systems:
			system.process_entities(entities, warm_delta, tick)

## Event-triggered systems (economy raid aftermath, save/load) never run from
## step() — callers invoke them explicitly when the triggering event occurs.
func trigger_cold_system(cold_name: StringName, delta: float = 0.0) -> void:
	var system: SystemBase = _cold_systems.get(cold_name)
	assert(system != null, "No COLD system registered as '%s'" % cold_name)
	system.process_entities(entities, delta, tick)
