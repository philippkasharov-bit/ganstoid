## UI1 (was NX1/TP1's top-middle box): first-day tips as a small card at the
## bottom left, for TIP_S seconds when TipSystem has a new one. What to do next
## and the hustles moved to the pager (PagerView), so the middle stays clear.
## Read-only.
class_name GuideView
extends PanelContainer

const WIDTH := 360.0
const TIP_S := 11.0
const BOTTOM := 64.0          # above the fps line and clear of the hotbar

var _world: World
var left_of: Control   # UI2: kept right of the icon column when they would meet
var _tip := Label.new()
var _seen := 0
var _tip_left := 0.0

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiPanel.card_style())
	_tip.add_theme_font_size_override("font_size", 14)
	_tip.add_theme_color_override("font_color", UiTheme.TEXT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size.x = WIDTH
	add_child(_tip)
	visible = false

func _process(delta: float) -> void:
	if _world == null:
		return
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player == null:
		visible = false
		return
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	if state.tip_serial != _seen:
		_seen = state.tip_serial
		_tip.text = "TIP   " + state.tip_text
		_tip_left = TIP_S
	_tip_left -= delta
	visible = _tip_left > 0.0 and state.tips_on
	modulate.a = clampf(_tip_left / 0.4, 0.0, 1.0)
	reset_size()
	var y := roundf(get_viewport_rect().size.y - size.y - BOTTOM)
	var x := UiTheme.MARGIN
	if left_of != null and left_of.visible and y < left_of.position.y + left_of.size.y:
		x = left_of.position.x + left_of.size.x + UiTheme.SPACE
	position = HudLayout.place(self, "tips", Vector2(x, y))
