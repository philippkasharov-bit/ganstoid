## Placeholder-visual factory: one flat-colored Node2D per entity, nothing
## more. No art pipeline exists yet -- Phase 0.5's job is proving entities
## render at all, not looking good. Swap these for real sprites once that's
## confirmed in the editor, not before.
class_name EntityVisualFactory
extends RefCounted

const BUILDING_SIZE := Vector2(28.0, 28.0)
const NPC_SIZE := Vector2(8.0, 8.0)

const BUILDING_COLORS := {
	GanstoidEnums.BuildingType.RESIDENCE: Color(0.3, 0.5, 0.8),
	GanstoidEnums.BuildingType.LEGIT_BUSINESS: Color(0.9, 0.7, 0.2),
	GanstoidEnums.BuildingType.ILLEGAL_FRONT: Color(0.7, 0.2, 0.2),
	GanstoidEnums.BuildingType.SAFEHOUSE: Color(0.4, 0.1, 0.5),
}

const NPC_COLOR := Color(0.85, 0.85, 0.85)
const PLAYER_COLOR := Color(0.1, 0.9, 0.3)

## Returns null for an entity with no visual yet (GangData, economy items --
## neither has a position; see World._get_entity_position) rather than a
## default shape nobody asked for. Caller (RenderSync) must handle null.
static func create_visual(entity: Entity) -> Node2D:
	var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
	if building != null:
		return _make_rect(BUILDING_SIZE, BUILDING_COLORS.get(building.building_type, Color.GRAY))

	# Checked before the generic NPC case: the player entity carries BOTH
	# PlayerStateData and NPCData (see PlayerFactory) -- without this order,
	# the player would render identically to every civilian.
	var player_state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
	if player_state != null:
		return _make_rect(NPC_SIZE, PLAYER_COLOR)

	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if npc != null:
		return _make_rect(NPC_SIZE, NPC_COLOR)

	return null

static func _make_rect(size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = size
	rect.position = -size / 2.0  # centered on the entity's position, not its corner
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # placeholder shapes shouldn't eat clicks
	return rect
