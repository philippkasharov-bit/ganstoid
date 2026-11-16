## NX1/TP1: top middle, under the "who sees you" eye: the next-step line
## (NextStep) and, under it, a first-day tip for TIP_S seconds when
## TipSystem has a new one. Read-only.
class_name GuideView
extends VBoxContainer

const TOP := 46.0          # under the detection eye
const WIDTH := 560.0
const TIP_S := 10.0
const REFRESH_S := 0.5

var _world: World
var _line := Label.new()
var _tip_box := PanelContainer.new()
var _tip := Label.new()
var _seen := 0
var _tip_left := 0.0
var _refresh := 0.0

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiTheme.GAP)
	var line_box := PanelContainer.new()
	line_box.add_theme_stylebox_override("panel", UiTheme.window_box(4))
	line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.add_theme_font_size_override("font_size", 13)
	_line.add_theme_color_override("font_color", UiTheme.ACCENT)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = WIDTH
	line_box.add_child(_line)
	add_child(line_box)
	_tip_box.add_theme_stylebox_override("panel", UiPanel.card_style())
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_font_size_override("font_size", 14)
	_tip.add_theme_color_override("font_color", UiTheme.TEXT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size.x = WIDTH
	_tip_box.add_child(_tip)
	add_child(_tip_box)
	_tip_box.visible = false
	visible = false

func _process(delta: float) -> void:
	if _world == null:
		return
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player == null or SimNav.active == null or not SimNav.active.usable():
		visible = false
		return
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	if state.tip_serial != _seen:
		_seen = state.tip_serial
		_tip.text = "Tip: " + state.tip_text
		_tip_left = TIP_S
	_tip_left -= delta
	_tip_box.visible = _tip_left > 0.0 and state.tips_on
	_tip_box.modulate.a = clampf(_tip_left / 0.4, 0.0, 1.0)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_line.text = NextStep.line(_world)
	(_line.get_parent() as Control).visible = _line.text != ""
	visible = _line.text != "" or _tip_box.visible
	reset_size()
	position = Vector2(roundf((get_viewport_rect().size.x - size.x) * 0.5), TOP)
