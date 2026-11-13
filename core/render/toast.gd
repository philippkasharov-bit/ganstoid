## UI2/HT1: big news (arrested, raided, a new rank or trait) as a short
## pop-up at the bottom centre; everyday lines float over your head instead
## (HaloText). Read-only.
class_name Toast
extends PanelContainer

const SECONDS := 4.0
var _world: World
var _label := Label.new()
var _seen := 0
var _left := 0.0

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiPanel.card_style())
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", UiPanel.TEXT)
	add_child(_label)
	visible = false

func _process(delta: float) -> void:
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if player == null:
		return
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	if state.message_serial != _seen:
		_seen = state.message_serial
		if not state.message_alert:
			return
		_label.text = state.last_message
		_left = SECONDS
		reset_size()
	_left -= delta
	visible = _left > 0.0
	modulate.a = clampf(_left / 0.4, 0.0, 1.0)   # fades out over the last moment
	var view := get_viewport_rect().size
	position = Vector2((view.x - size.x) * 0.5, view.y - size.y - 72.0)   # above the hotbar
