## UI3: the moments that should feel good (or bad) get a stamp in the middle
## of the screen: a new rank, a hustle done, caught with your hand in a pocket.
## Systems set PlayerStateData.stamp and bump stamp_serial; this slams it down
## (big, tilted, scaled in) and fades it out. Money you gain or lose floats up
## from your figure ("+$120", "-$40"). Read-only.
class_name StampView
extends Control

const STAMP_S := 2.4
const POP_S := 1.3
const TILT := -0.12

var _world: World
var _seen := 0
var _t := 99.0
var _text := ""
var _sub := ""
var _color := UiTheme.ACCENT
var _last_cash := -1
var _pops: Array = []      # [text, colour, age]

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var npc: NPCData = p.get_component(ComponentNames.NPC)
	if state.stamp_serial != _seen:
		_seen = state.stamp_serial
		_text = String(state.stamp.get("text", ""))
		_sub = String(state.stamp.get("sub", ""))
		_color = state.stamp.get("color", UiTheme.ACCENT)
		_t = 0.0
	_t += delta
	var cash := npc.cash
	if _last_cash >= 0 and cash != _last_cash and GameRules.of(_world) != null:
		var d := cash - _last_cash
		_pops.append(["%s$%d" % ["+" if d > 0 else "-", absi(d)], UiTheme.GOOD if d > 0 else UiTheme.BAD, 0.0])
	_last_cash = cash
	for pop in _pops:
		pop[2] += delta
	_pops = _pops.filter(func(pop: Array) -> bool: return pop[2] < POP_S)
	queue_redraw()

func _draw() -> void:
	var view := get_viewport_rect().size
	if _t < STAMP_S and _text != "":
		var slam := clampf(_t / 0.18, 0.0, 1.0)
		var scale := lerpf(2.2, 1.0, ease(slam, 0.4))
		var a := clampf((STAMP_S - _t) / 0.5, 0.0, 1.0) * slam
		var font := UiTheme.font("marker")
		var size := 54
		var w := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_set_transform(Vector2(view.x * 0.5, view.y * 0.24), TILT, Vector2.ONE * scale)
		var box := Rect2(Vector2(-w * 0.5 - 18, -size * 0.95), Vector2(w + 36, size * 1.35 + (24.0 if _sub != "" else 0.0)))
		draw_rect(box, Color(0, 0, 0, 0.55 * a))
		draw_rect(box, Color(_color, a), false, 4.0)
		draw_string(font, Vector2(-w * 0.5, 0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(_color, a))
		if _sub != "":
			var sf := UiTheme.font("bungee")
			var sw := sf.get_string_size(_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(sf, Vector2(-sw * 0.5, size * 0.42 + 14), _sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, a))
		draw_set_transform(Vector2.ZERO)
	if _pops.is_empty():
		return
	var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var at := ScreenMap.to_screen(get_viewport(), me.position, 2.0) + Vector2(18, -40)
	var bf := UiTheme.font("bungee")
	for i in _pops.size():
		var pop: Array = _pops[i]
		var f: float = pop[2] / POP_S
		var col: Color = pop[1]
		var pos := at + Vector2(0, -42.0 * f - 20.0 * i)
		draw_string_outline(bf, pos, pop[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0, 0, 0, 1.0 - f))
		draw_string(bf, pos, pop[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(col, 1.0 - f))

## Sets a stamp for the HUD to show.
static func put(state: PlayerStateData, text: String, sub: String = "", color: Color = UiTheme.ACCENT) -> void:
	state.stamp = {"text": text, "sub": sub, "color": color}
	state.stamp_serial += 1
