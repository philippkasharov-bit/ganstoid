## PH1: a new phone message slides in under the pager for SHOW_S seconds:
## who it's from and the first line, like a phone notification. Read-only.
class_name NotifyView
extends PanelContainer

const SHOW_S := 5.0
const WIDTH := 300.0

var pager: Control
var _world: World
var _from := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.ACCENT)
var _text := UiTheme.label("", UiTheme.FONT_BODY, UiTheme.TEXT)
var _seen := -1
var _left := 0.0

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiPanel.card_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = WIDTH
	col.add_child(_from)
	col.add_child(_text)
	add_child(col)
	visible = false

func _process(delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var n := state.inbox.size()
	var newest: Dictionary = state.inbox[n - 1] if n > 0 else {}
	var id := int(newest.get("at", -1)) * 31 + n
	if _seen == -1:
		_seen = id   # what was there when the game loaded is old news
	elif id != _seen:
		_seen = id
		_from.text = "MESSAGE  ·  " + String(newest.get("from", "")) + "   (P)"
		_text.text = String(newest.get("text", ""))
		_left = SHOW_S
	_left -= delta
	visible = _left > 0.0
	if not visible:
		return
	var slide := clampf((SHOW_S - _left) / 0.25, 0.0, 1.0)
	modulate.a = clampf(_left / 0.5, 0.0, 1.0)
	reset_size()
	var right := pager.position.x + pager.size.x if pager != null and pager.visible else get_viewport_rect().size.x - UiTheme.MARGIN
	var top := pager.position.y + pager.size.y + UiTheme.SPACE if pager != null and pager.visible else 80.0
	position = Vector2(roundf(right - size.x + (1.0 - slide) * 60.0), roundf(top))
