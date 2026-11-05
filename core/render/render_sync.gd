## The ONE place rendering touches Godot's scene tree -- mirrors
## world_driver.gd's role for simulation (that file's doc comment now says
## "simulation layer" specifically, not "everything," since this exists as
## its sibling on the render side). World itself stays engine-agnostic:
## this is a consumer that reads it, never the other way around. It never
## writes to World.entities or World._component_index -- only reads them,
## per the read-only contract on World.entities / get_entities_with_component.
##
## Diffs World.entities against its own tracked visual-node dict every
## frame: new entity ids get a visual spawned (EntityVisualFactory),
## removed ids get their visual freed, existing ones get repositioned.
## Runs on _process (render-rate), not _physics_process (sim-rate) --
## visuals should update as smoothly as the engine allows regardless of
## how often the sim itself ticks.
extends Node2D

## Sibling WorldDriver node in the scene tree. Exported (set in the editor)
## rather than a hardcoded get_node path, so this doesn't assume one fixed
## scene layout.
@export var world_driver_path: NodePath

var _world: World
var _visuals: Dictionary = {}  # StringName -> Node2D

func _ready() -> void:
	var driver: Node = get_node(world_driver_path)
	_world = driver.world

func _process(_delta: float) -> void:
	if _world == null:
		return
	_sync_visuals()

func _sync_visuals() -> void:
	for id in _world.entities:
		var entity: Entity = _world.entities[id]
		if not _visuals.has(id):
			var visual := EntityVisualFactory.create_visual(entity)
			if visual == null:
				continue  # no visual for this entity type yet -- see the factory
			add_child(visual)
			_visuals[id] = visual
		_sync_position(id, entity)
	_remove_stale_visuals()

func _sync_position(id: StringName, entity: Entity) -> void:
	var visual: Node2D = _visuals[id]
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if npc != null:
		visual.position = npc.position
		return
	var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
	if building != null:
		visual.position = building.position

## Entities that left World.entities (future despawn/death systems) need
## their visual freed too, or RenderSync leaks a Node2D per removed entity
## forever. Iterates a snapshot (.keys()) specifically so erasing from
## _visuals mid-loop is safe.
func _remove_stale_visuals() -> void:
	for id in _visuals.keys():
		if not _world.entities.has(id):
			_visuals[id].queue_free()
			_visuals.erase(id)
