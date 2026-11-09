## Orchestrator: owns all entities, runs systems at their declared tick_rate.
## step() is called by a driver (Godot _physics_process, or a headless test
## loop) — World itself never touches the scene tree, keeping it testable
## and deterministic independent of frame rate.
class_name World
extends RefCounted

## Warm systems run once every N ticks rather than every tick — tunable per
## playtesting, not a magic number baked into call sites.
const WARM_TICK_INTERVAL := 10

## StringName -> Entity. A LIVE reference, not a snapshot -- callers (and
## systems receiving this or get_entities_with_component's result as their
## process_entities entities param) must treat it read-only. Add/remove
## entities only through register_entity/unregister_entity; mutating this
## dict directly desyncs _component_index and spatial_index from it.
var entities: Dictionary = {}
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

## For in-play random rolls (crime outcomes, witness recognition) --
## deliberately NOT the same RNG/seed as worldgen (CityGenerator,
## PopulationSeeder each take their own explicit seed for deterministic city
## generation). Two different playthroughs of the same city seed should
## still have crimes land differently, so this one self-seeds by default.
var runtime_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## good_id -> EconomyItemData. Not entity-backed (goods aren't positioned,
## don't need the spatial index or component index) -- a fixed catalog
## seeded once by GoodsCatalog at new-game start, mutated in place by
## EconomySystem and any future buy/sell action. Same "live reference,
## read-only to callers that aren't the owning system" contract as
## `entities`/`_component_index` above.
var economy_items: Dictionary = {}

var tick: int = 0

func register_entity(entity: Entity) -> void:
	entities[entity.id] = entity
	for component_name in entity.components:
		if not _component_index.has(component_name):
			_component_index[component_name] = {}
		_component_index[component_name][entity.id] = entity
	var position: Variant = _get_entity_position(entity)
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
## entity has ever registered that component. LIVE reference into
## _component_index, same read-only contract as the `entities` field --
## a system that calls .erase()/[]= on what it's handed corrupts the index
## rather than just failing to see its own change.
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
	var position: Variant = _get_entity_position(entity)
	if position != null:
		spatial_index.update(id, position)

## Call this after calling add_component/remove_component on an entity
## that's already registered — same staleness problem as position, just for
## _component_index instead of spatial_index: register_entity only indexes
## the component set it saw at registration time, so a later add/remove
## goes stale (entity missing from a bucket it just gained, or stuck in one
## it just lost) until this runs. Cheap full resync rather than a delta
## update — component sets change rarely compared to position, so there's
## no warm-tick-budget reason to make this incremental.
func reindex_components(id: StringName) -> void:
	var entity: Entity = entities.get(id)
	if entity == null:
		return
	for component_name in _component_index:
		_component_index[component_name].erase(id)
	for component_name in entity.components:
		if not _component_index.has(component_name):
			_component_index[component_name] = {}
		_component_index[component_name][id] = entity

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
