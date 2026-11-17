## BZ4: the cook. A heat gauge that creeps up on its own: the green band is
## where the good stuff comes from, the red line is a fire. Heat and Cool
## (the buttons, or the left and right arrow keys) nudge it; the clock shows what's left.
## Read-only: the buttons only ask (ui_lab).
class_name CookWindow
extends PanelContainer

const W := 340.0
const H := 26.0

var _world: World
var _gauge := Control.new()
var _info := Label.new()

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiPanel.card_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var title := UiTheme.label("THE COOK", 22, UiTheme.ACCENT)
	title.add_theme_font_override("font", UiTheme.font("marker"))
	col.add_child(title)
	_gauge.custom_minimum_size = Vector2(W, H)
	_gauge.draw.connect(_draw_gauge)
	col.add_child(_gauge)
	col.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for spec in [["< Cool", -1.0], ["Heat >", 1.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		var dir: float = spec[1]
		b.pressed.connect(func() -> void: _ask(dir))
		row.add_child(b)
	col.add_child(row)
	visible = false

func _ask(dir: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p != null:
		(p.get_component(ComponentNames.PLAYER_STATE) as PlayerStateData).ui_lab = {"heat": dir}

func _process(_delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
	visible = state != null and not state.cook.is_empty()
	if not visible:
		return
	if _edge(KEY_LEFT):
		_ask(-1.0)
	if _edge(KEY_RIGHT):
		_ask(1.0)
	var c := state.cook
	_info.text = "%d s left  ·  in the green %d s  ·  %d boxes" % [ceili(DrugLabSystem.COOK_S - float(c["t"])), roundi(float(c["green"])), int(c["boxes"])]
	_gauge.queue_redraw()
	var view := get_viewport_rect().size
	position = Vector2(((view.x - size.x) * 0.5), view.y * 0.62).round()

var _down := {}
## True on the frame a key goes down.
func _edge(key: Key) -> bool:
	var now := Input.is_key_label_pressed(key)
	var was: bool = _down.get(key, false)
	_down[key] = now
	return now and not was

func _draw_gauge() -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
	if state == null or state.cook.is_empty():
		return
	_gauge.draw_rect(Rect2(0, 0, W, H), Color(0.32, 0.3, 0.28))   # the track
	var g := DrugLabSystem.GREEN
	_gauge.draw_rect(Rect2(W * g.x, 0, W * (g.y - g.x), H), Color(UiTheme.GOOD, 0.55))
	_gauge.draw_rect(Rect2(W * DrugLabSystem.FIRE_AT, 0, W * (1.0 - DrugLabSystem.FIRE_AT), H), Color(UiTheme.BAD, 0.7))
	var x := W * float(state.cook["heat"])
	_gauge.draw_rect(Rect2(x - 2, -3, 4, H + 6), Color.WHITE)
