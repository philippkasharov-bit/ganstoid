## INV4: piles you dropped, drawn where they lie: the item's picture on a dark
## disc, the count beside it when more than one. Screen-space over the map.
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
	var xf := get_viewport().get_canvas_transform()
	for pile in state.ground:
		var at: Vector2 = xf * pile["pos"]
		if not view.has_point(at):
			continue
		draw_circle(at, SIZE * 0.7, Color(0, 0, 0, 0.55))
		var kind: String = ItemCatalog.item(pile["id"]).get("kind", "goods")
		ItemArt.draw(self, pile["id"], Rect2(at - Vector2(SIZE, SIZE) * 0.5, Vector2(SIZE, SIZE)), InventoryWindow.KIND_COLOURS.get(kind, Color.WHITE), false)
		if int(pile["n"]) > 1:
			draw_string(ThemeDB.fallback_font, at + Vector2(SIZE * 0.6, SIZE * 0.6), "x%d" % int(pile["n"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiTheme.ACCENT)
