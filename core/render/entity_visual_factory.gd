## Placeholder-visual factory: one flat-colored Node2D per entity, nothing
## more. No art pipeline exists yet -- Phase 0.5's job is proving entities
## render at all, not looking good. Swap these for real sprites once that's
## confirmed in the editor, not before.
class_name EntityVisualFactory
extends RefCounted

const BUILDING_MARK_M := 3.0   # role marker at a building's door (the building itself is drawn by the city map)
const PERSON_RADIUS_M := 1.0   # drawn a bit larger than a body so people read at street zoom

const BUILDING_COLORS := {
	GanstoidEnums.BuildingType.RESIDENCE: Color(0.3, 0.5, 0.8),
	GanstoidEnums.BuildingType.LEGIT_BUSINESS: Color(0.9, 0.7, 0.2),
	GanstoidEnums.BuildingType.ILLEGAL_FRONT: Color(0.7, 0.2, 0.2),
	GanstoidEnums.BuildingType.SAFEHOUSE: Color(0.4, 0.1, 0.5),
}

const NPC_COLOR := Color(0.36, 0.38, 0.45)   # dark enough to read on the light map
const COP_COLOR := Color(0.2, 0.85, 0.95)
const DEALER_COLOR := Color(0.95, 0.55, 0.1)
const PLAYER_COLOR := Color(0.1, 0.9, 0.3)

## Returns null for an entity with no visual yet (GangData, economy items --
## neither has a position; see World._get_entity_position) rather than a
## default shape nobody asked for. Caller (RenderSync) must handle null.
static func create_visual(entity: Entity) -> Node2D:
	var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
	if building != null:
		if building.building_type == GanstoidEnums.BuildingType.RESIDENCE:
			return null   # thousands of homes: the map already shows them
		return _make_rect(Vector2.ONE * BUILDING_MARK_M, BUILDING_COLORS.get(building.building_type, Color.GRAY))

	# Checked before the generic NPC case: the player entity carries BOTH
	# PlayerStateData and NPCData (see PlayerFactory) -- without this order,
	# the player would render identically to every civilian.
	var player_state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
	if player_state != null:
		return _make_person(PLAYER_COLOR, 1.4, Color.WHITE)

	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if npc != null:
		if npc.is_cop:
			return _make_person(COP_COLOR)
		if npc.is_dealer:
			return _make_person(DEALER_COLOR)
		return _make_person(NPC_COLOR)

	return null

## Polygon2D, not ColorRect: ColorRect extends Control (a UI node, meant for
## screen-space overlays), not Node2D -- using it for world-space entities
## was a real type error, not a style choice, caught by Godot rejecting the
## ColorRect-typed return against this function's Node2D-typed one.
static func _make_rect(size: Vector2, color: Color) -> Node2D:
	var half := size / 2.0
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	poly.color = color
	return poly

## A person: filled dot with a dark rim so it reads on both day and night maps.
static func _make_person(color: Color, scale: float = 1.0, rim: Color = Color(0.08, 0.08, 0.1)) -> Node2D:
	var dot := Node2D.new()
	var r := PERSON_RADIUS_M * scale
	dot.draw.connect(func() -> void:
		dot.draw_circle(Vector2.ZERO, r + 0.35, rim)
		dot.draw_circle(Vector2.ZERO, r, color))
	return dot
