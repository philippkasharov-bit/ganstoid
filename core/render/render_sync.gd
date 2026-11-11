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

const DOWN_TINT := Color(0.55, 0.12, 0.1)
const KO_TINT := Color(0.55, 0.55, 0.7)

var _world: World
var _visuals: Dictionary = {}  # StringName -> Node2D
var _visuals_for := -1          # entity count the visuals were last built for

func _ready() -> void:
	var driver: Node = get_node(world_driver_path)
	_world = driver.world

func _process(_delta: float) -> void:
	if _world == null:
		return
	_sync_visuals()

## S1: visuals are created for any new entity, but only people are re-positioned
## each frame (buildings never move), and people who are indoors are hidden.
func _sync_visuals() -> void:
	if _visuals_for != _world.entities.size():
		_visuals_for = _world.entities.size()
		for id in _world.entities:
			if not _visuals.has(id):
				var visual := EntityVisualFactory.create_visual(_world.entities[id])
				if visual == null:
					continue  # no visual for this entity type yet -- see the factory
				add_child(visual)
				_visuals[id] = visual
				var building: BuildingData = _world.entities[id].get_component(ComponentNames.BUILDING)
				if building != null:
					visual.position = building.position
		_remove_stale_visuals()
	var people := _world.get_entities_with_component(ComponentNames.NPC)
	for id in people:
		var visual: Node2D = _visuals.get(id)
		if visual == null:
			continue
		var npc: NPCData = people[id].get_component(ComponentNames.NPC)
		visual.visible = not npc.indoors and not (people[id].has_component(ComponentNames.PLAYER_STATE) and _in_car(people[id]))
		if visual.visible:
			var moved: Vector2 = npc.position - visual.position
			if people[id].has_component(ComponentNames.PLAYER_STATE):
				var st: PlayerStateData = people[id].get_component(ComponentNames.PLAYER_STATE)
				if st.aim_point != npc.position:
					visual.rotation = (st.aim_point - npc.position).angle()   # the player faces the mouse
			elif moved.length_squared() > 0.0004 and moved.length_squared() < 25.0:
				visual.rotation = lerp_angle(visual.rotation, moved.angle(), 0.3)   # NPCs face where they walk
			visual.position = npc.position
			var tint := Color.WHITE if not npc.is_down else (KO_TINT if npc.ko_until_tick >= 0 else DOWN_TINT)
			if visual.modulate != tint:
				visual.modulate = tint   # combat: a body on the ground, or someone out cold
				var base: float = 1.6 * (1.15 if people[id].has_component(ComponentNames.PLAYER_STATE) else 1.0)
				visual.scale = Vector2(base * 1.3, base * 0.8) if npc.is_down else Vector2.ONE * base   # lying flat

	for id in _world.get_entities_with_component(ComponentNames.VEHICLE):
		var car_visual: Node2D = _visuals.get(id)
		if car_visual != null:
			var car: VehicleData = _world.entities[id].get_component(ComponentNames.VEHICLE)
			car_visual.position = car.position
			car_visual.rotation = car.heading

static func _in_car(player: Entity) -> bool:
	return (player.get_component(ComponentNames.PLAYER_STATE) as PlayerStateData).vehicle_id != &""

func _remove_stale_visuals() -> void:
	for id in _visuals.keys():
		if not _world.entities.has(id):
			_visuals[id].queue_free()
			_visuals.erase(id)
