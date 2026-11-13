## INV4: piles you dropped, drawn where they lie: the item's picture on a dark
## disc, the count beside it when more than one. Screen-space over the map
## (2D or 3D, through ScreenMap).
class_name GroundView
extends Control

const SIZE := 16.0

var _world: World

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var view := get_viewport_rect().grow(SIZE)
	for pile in state.ground:
		var at: Vector2 = ScreenMap.to_screen(get_viewport(), pile["pos"], 0.1)   # R3D13: either view
		if not view.has_point(at):
			continue
		draw_circle(at, SIZE * 0.7, Color(0, 0, 0, 0.55))
		var kind: String = ItemCatalog.item(pile["id"]).get("kind", "goods")
		ItemArt.draw(self, pile["id"], Rect2(at - Vector2(SIZE, SIZE) * 0.5, Vector2(SIZE, SIZE)), InventoryWindow.KIND_COLOURS.get(kind, Color.WHITE), false)
		if int(pile["n"]) > 1:   # UIF2: the count on a dark pill, readable on the bright map
			var text := "%d" % int(pile["n"])
			var pill := Rect2(at + Vector2(SIZE * 0.45, SIZE * 0.2), Vector2(8 + 6 * text.length(), 12))
			draw_rect(pill, Color(0, 0, 0, 0.7))
			draw_string(ThemeDB.fallback_font, pill.position + Vector2(4, 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiTheme.TEXT)
