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

	var car: VehicleData = entity.get_component(ComponentNames.VEHICLE)
	if car != null:
		return _make_car(car)

	# Checked before the generic NPC case: the player entity carries BOTH
	# PlayerStateData and NPCData (see PlayerFactory) -- without this order,
	# the player would render identically to every civilian.
	var player_state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
	if player_state != null:
		return _make_person(PLAYER_COLOR, 1.15, Color.WHITE, &"player")

	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	if npc != null:
		if npc.is_cop:
			return _make_person(COP_COLOR, 1.0, Color(0.08, 0.08, 0.1), &"cop")
		if npc.is_fixer:   # JB1: a fixer stands out a little to those who know
			return _make_person(Color(0.75, 0.5, 0.95), 1.0, Color(0.08, 0.08, 0.1), &"fixer")
		if npc.is_dealer:
			return _make_person(DEALER_COLOR, 1.0, Color(0.08, 0.08, 0.1), &"dealer")
		return _make_person(NPC_COLOR, 1.0, Color(0.08, 0.08, 0.1), &"civilian")

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

## V1: a car seen from above: body, darker roof, windscreen toward the front (+x).
static func _make_car(car: VehicleData) -> Node2D:
	var node := Node2D.new()
	node.position = car.position
	node.rotation = car.heading   # parked cars are placed once here (RenderSync only moves touched ones)
	var half := Vector2(car.length_m, car.width_m) * 0.5
	var body := Rect2(-half, half * 2.0)
	var roof := Rect2(Vector2(-half.x * 0.55, -half.y * 0.8), Vector2(half.x * 1.0, half.y * 1.6))
	var glass := Rect2(Vector2(half.x * 0.45, -half.y * 0.75), Vector2(half.x * 0.22, half.y * 1.5))
	node.draw.connect(func() -> void:
		node.draw_rect(body.grow(0.08), Color(0.05, 0.05, 0.06))
		node.draw_rect(body, car.color)
		node.draw_rect(roof, car.color.darkened(0.25))
		node.draw_rect(glass, Color(0.55, 0.7, 0.8)))
	return node

## A person: filled dot with a dark rim so it reads on both day and night maps.
## Placeholder body (box model): shoulders box + head box, nose toward +x so
## the node's rotation is the way they face. ART SWAP POINT: drop a scene at
## res://art/characters/<kind>.tscn (kind = player, civilian, cop, dealer) and
## it is used instead, rotated the same way; nothing else needs to change.
const ART_DIR := "res://art/characters/"

static func _make_person(color: Color, scale: float = 1.0, rim: Color = Color(0.08, 0.08, 0.1), kind: StringName = &"civilian") -> Node2D:
	var art := ART_DIR + String(kind) + ".tscn"
	if ResourceLoader.exists(art):
		return (load(art) as PackedScene).instantiate() as Node2D
	var body := Node2D.new()
	var shoulders := Rect2(Vector2(-0.22, -0.3), Vector2(0.44, 0.6)).grow(0.0)
	var head := Rect2(Vector2(-0.12, -0.13), Vector2(0.26, 0.26))
	body.scale = Vector2.ONE * scale * 1.6   # drawn a bit larger than life so people read at street zoom
	body.draw.connect(func() -> void:
		body.draw_rect(shoulders.grow(0.06), rim)
		body.draw_rect(shoulders, color)
		body.draw_rect(head.grow(0.04), rim)
		body.draw_rect(head, color.lightened(0.35))
		body.draw_rect(Rect2(Vector2(0.14, -0.05), Vector2(0.1, 0.1)), rim))   # nose: which way they face
	return body
