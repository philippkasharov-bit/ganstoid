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

## Archetype-lite index: component name -> Dictionary[StringName, Entity] of
## every entity that currently has that component. Rebuilt incrementally on
## register/unregister rather than scanned fresh each tick — this is what
## lets a system declare required_component and get an O(matching) view
## instead of O(all entities) every tick.
var _component_index: Dictionary = {}  # StringName -> Dictionary[StringName, Entity]

var spatial_index: SpatialIndex = SpatialIndex.new()
var event_bus: EventBus = EventBus.new()

var tick: int = 0

func register_entity(entity: Entity) -> void:
	entities[entity.id] = entity
	for component_name in entity.components:
		if not _component_index.has(component_name):
			_component_index[component_name] = {}
		_component_index[component_name][entity.id] = entity
	var position := _get_entity_position(entity)
	if position != null:
		spatial_index.insert(entity.id, position)

func unregister_entity(id: StringName) -> void:
	var entity: Entity = entities.get(id)
	if entity != null:
		for component_name in entity.components:
			if _component_index.has(component_name):
				_component_index[component_name].erase(id)
		spatial_index.remove(id)
	entities.erase(id)

## Pre-indexed view of every entity holding component_name — O(matching),
## not O(all entities). Returns an empty Dictionary (never null) if no
## entity has ever registered that component.
func get_entities_with_component(component_name: StringName) -> Dictionary:
	return _component_index.get(component_name, {})

## Entities don't expose position uniformly (NPCData.position vs
## BuildingData.position aren't a shared interface) — this is the one place
## that knows how to find a position to feed the spatial index. Extend the
## match as new positioned components are added; a component type with no
## case here just never enters the spatial index, which is the safe default.
func _get_entity_position(entity: Entity) -> Variant:
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if npc != null:
		return npc.position
	var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
	if building != null:
		return building.position
	return null

## Call this after moving an entity's position (NPC movement system, Phase 1+)
## — register_entity only indexes position at registration time, so a moved
## entity goes stale in spatial_index until this is called.
func reindex_position(id: StringName) -> void:
	var entity: Entity = entities.get(id)
	if entity == null:
		return
	var position := _get_entity_position(entity)
	if position != null:
		spatial_index.update(id, position)

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
		system.process_entities(_entities_for(system), delta, tick)
	if tick % WARM_TICK_INTERVAL == 0:
		var warm_delta := delta * WARM_TICK_INTERVAL
		for system in _warm_systems:
			system.process_entities(_entities_for(system), warm_delta, tick)

## Event-triggered systems (economy raid aftermath, save/load) never run from
## step() — callers invoke them explicitly when the triggering event occurs.
func trigger_cold_system(cold_name: StringName, delta: float = 0.0) -> void:
	var system: SystemBase = _cold_systems.get(cold_name)
	assert(system != null, "No COLD system registered as '%s'" % cold_name)
	system.process_entities(_entities_for(system), delta, tick)

func _entities_for(system: SystemBase) -> Dictionary:
	if system.required_component == &"":
		return entities
	return get_entities_with_component(system.required_component)
