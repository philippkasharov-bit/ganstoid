## UI9: DayZ-style status bar, bottom-right. The core needs are always on
## screen as flat white icons that turn yellow, orange and red as they run
## low (red ones pulse), with ↑/↓ arrows showing how fast they are rising or
## falling and the % under each. Problems (bleeding, wanted, warrant, heavy)
## appear to the left only while they apply. Click an icon for the obvious
## fix; hover for what it means. Reads state; the one write is state.ui_use.
class_name Moodles
extends HBoxContainer

const ICON := 40.0
const CELL := Vector2(52, 78)
const OK := Color(0.93, 0.93, 0.9)
const STATE_COLOURS := [OK, Color("e8c547"), Color("e8913a"), Color("e0533d")]
const REFRESH_S := 0.25
const TREND_S := 1.0                      # real seconds between trend samples
const ARROW_PER_DAY := [0.15, 0.9, 3.0]   # change per game day for 1, 2, 3 arrows

## [key (icon file + npc field), name, what a click does, why it matters]
## UI10: each icon keeps its own colour (what it is); how bad it is shows in
## the frame, arrows and number (white fine, then yellow, orange, red).
const IDENTITY := {
	"hunger": Color("e0a050"), "thirst": Color("4fa8e8"), "fatigue": Color("f2d34b"),
	"health": Color("e4574f"), "calm": Color("5cc85a"), "bleeding": Color("ff4a55"),
	"wanted": Color("5a8cf0"), "warrant": Color("e8b35a"), "heavy": Color("a8a8a0"),
}

## UI11: food and water icons run red (empty) through yellow to green (full).
const GAUGE := ["hunger", "thirst"]

static func gauge_colour(v: float) -> Color:
	var red := Color("e0533d")
	var yellow := Color("e8c547")
	var green := Color("5cc85a")
	return red.lerp(yellow, v * 2.0) if v < 0.5 else yellow.lerp(green, (v - 0.5) * 2.0)

const NEEDS := [
	["hunger", "Food", "food", "Click: eat the most filling food you carry."],
	["thirst", "Water", "drink", "Click: drink the best drink you carry."],
	["fatigue", "Energy", "sleep", "Click: sleep here (Z). Sleep somewhere safe."],
	["health", "Health", "medical", "Click: apply a bandage. Rest heals."],
	["calm", "Happiness", "", "Stress spoils aim and talk. Stay out of trouble."],
]

var _world: World
var _left := 0.0
var _trend_left := 0.0
var _before := {}
var _before_tick := 0
var _trend := {}
var _key := ""
var _pulse := 0.0
var _tip := UiTooltip.new()

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 2)
	alignment = BoxContainer.ALIGNMENT_END
	add_child(_tip)
	_tip.top_level = true

## The 0..1 "how full" value for a need (stress is shown as calm).
static func value(npc: NPCData, key: String) -> float:
	return 1.0 - npc.stress if key == "calm" else float(npc.get(key))

## 0 fine, 1 low, 2 very low, 3 critical.
static func level_of(v: float) -> int:
	if v < 0.15:
		return 3
	if v < 0.3:
		return 2
	return 1 if v < 0.5 else 0

## Conditional problems as [icon key, name, badge, why, act].
static func notices(npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	if npc.bleeding:
		out.append(["bleeding", "Bleeding", "-%d/m" % roundi(WoundSystem.BLEED_PER_MIN * 100), "Losing %d%% health a minute. Click: apply a bandage." % roundi(WoundSystem.BLEED_PER_MIN * 100), "medical"])
	if state.law_tier > 0:
		out.append(["wanted", "Wanted", "%d/4" % state.law_tier, "Heat level %d of 4. Get out of sight and it cools." % state.law_tier, ""])
	if state.case_evidence >= CaseSystem.WARRANT_AT:
		out.append(["warrant", "Warrant", str(roundi(state.case_evidence)), "Case %d (warrant at %d). Cops arrest on sight." % [roundi(state.case_evidence), roundi(CaseSystem.WARRANT_AT)], ""])
	var kg := InventoryWindow.carried_kg(state)
	if kg > ItemCatalog.CARRY_KG:
		out.append(["heavy", "Heavy load", "%.0fkg" % kg, "%.1f of %.0f kg. Click: open the bag." % [kg, ItemCatalog.CARRY_KG], "bag"])
	return out

## Arrows from a change per game day: positive up, negative down, 0..3 each way.
static func arrows(per_day: float) -> int:
	var n := 0
	for edge in ARROW_PER_DAY:
		if absf(per_day) >= edge:
			n += 1
	return n if per_day > 0.0 else -n

func _process(delta: float) -> void:
	if _world == null:
		return
	_pulse += delta
	_left -= delta
	_trend_left -= delta
	position = get_viewport_rect().size - size - Vector2(14, 10)
	if _left > 0.0:
		_blink()
		return
	_left = REFRESH_S
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	visible = p != null and GameRules.of(_world) != null
	if not visible:
		return
	var npc: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	if _trend_left <= 0.0:
		_trend_left = TREND_S
		_sample_trend(npc)
	var key := _state_key(npc, state)
	if key != _key:
		_key = key
		_rebuild(npc, state)

func _sample_trend(npc: NPCData) -> void:
	var ticks := _world.tick - _before_tick
	for need in NEEDS:
		var now := value(npc, need[0])
		if _before.has(need[0]) and ticks > 0:
			_trend[need[0]] = arrows((now - _before[need[0]]) / ticks * SimClock.day_ticks)
		_before[need[0]] = now
	_before_tick = _world.tick

func _state_key(npc: NPCData, state: PlayerStateData) -> String:
	var parts: PackedStringArray = []
	for need in NEEDS:
		parts.append("%d%d" % [roundi(value(npc, need[0]) * 100), _trend.get(need[0], 0)])
	for n in notices(npc, state):
		parts.append(n[0] + n[2])
	return ",".join(parts)

func _rebuild(npc: NPCData, state: PlayerStateData) -> void:
	for c in get_children():
		if c != _tip:
			remove_child(c)
			c.queue_free()
	for n in notices(npc, state):
		add_child(_cell(n[0], n[1], 3, "", n[2], n[3], n[4]))
	for need in NEEDS:
		var v := value(npc, need[0])
		var t: int = _trend.get(need[0], 0)
		var why := "%d%% %s. %s" % [roundi(v * 100), "rising" if t > 0 else ("falling" if t < 0 else "steady"), need[3]]
		add_child(_cell(need[0], need[1], level_of(v), ("↑" if t > 0 else "↓").repeat(absi(t)), "%d%%" % roundi(v * 100), why, need[2], gauge_colour(v) if need[0] in GAUGE else Color.TRANSPARENT))

func _cell(icon: String, name: String, level: int, arrow_text: String, number: String, why: String, act: String, tint: Color = Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CELL
	var back := UiTheme.box(Color(0.05, 0.05, 0.06, 0.62), STATE_COLOURS[level] if level > 0 else Color.TRANSPARENT, 2 if level > 0 else 0)
	back.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", back)
	b.add_theme_stylebox_override("pressed", back)
	var hover := back.duplicate()
	hover.bg_color = Color(0.12, 0.12, 0.13, 0.8)
	b.add_theme_stylebox_override("hover", hover)
	b.set_meta("level", level)
	var col: Color = STATE_COLOURS[level]
	var arrow := UiTheme.label(arrow_text, 13, col)
	arrow.position = Vector2(0, 0)
	arrow.size = Vector2(CELL.x, 14)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var art := icon_or_glyph(icon, name.left(1), ICON)
	art.position = Vector2((CELL.x - ICON) * 0.5, 15)
	art.modulate = tint if tint.a > 0.0 else IDENTITY.get(icon, col)
	var num := UiTheme.label(number, 12, tint.lightened(0.2) if tint.a > 0.0 else (col if level > 0 else IDENTITY.get(icon, col).lightened(0.35)))
	num.position = Vector2(0, 15 + ICON + 2)
	num.size = Vector2(CELL.x, 14)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for part in [arrow, art, num]:
		_shadow(part)
		b.add_child(part)
	b.mouse_entered.connect(func() -> void: _tip.show_at(b.global_position + Vector2(-260, -40), "%s  (%s)" % [name, ["fine", "low", "very low", "critical"][level]], [[why, UiTheme.TEXT]]))
	b.mouse_exited.connect(_tip.hide_tip)
	b.pressed.connect(func() -> void: _act(act))
	return b

static func _shadow(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if c is Label:
		c.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		c.add_theme_constant_override("outline_size", 4)

## Critical icons pulse, like DayZ's blinking red.
func _blink() -> void:
	var a := 0.55 + 0.45 * absf(sin(_pulse * 4.0))
	for c in get_children():
		if c is Button and c.get_meta("level", 0) == 3:
			var frame: StyleBoxFlat = c.get_theme_stylebox("normal")
			frame.border_color.a = a   # only the red frame pulses; the icon stays readable
			frame.bg_color = Color(0.2, 0.03, 0.05, 0.7 * a)

## UI7: art/ui/needs/<name>.png (flat white, tinted here) when present, then
## art/ui/icons/<name>.png, else the letter (art swap point).
static func icon_or_glyph(name: String, glyph: String, px: float) -> Control:
	for dir in ["needs", "icons"]:
		var path := "res://art/ui/%s/%s.png" % [dir, name]
		if ResourceLoader.exists(path):
			var tex := TextureRect.new()
			tex.texture = load(path)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.custom_minimum_size = Vector2(px, px)
			tex.size = Vector2(px, px)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return tex
	var l := UiTheme.label(glyph, 22, Color(1, 1, 1, 0.92))
	l.size = Vector2(px, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l

## UI8: the small number in a corner of an icon.
static func badge(text: String, colour: Color) -> Label:
	var l := UiTheme.label(text, 11, Color.WHITE)
	var bg := UiTheme.box(colour.darkened(0.2), Color(0, 0, 0, 0.8), 1)
	bg.set_content_margin_all(0)
	bg.content_margin_left = 3
	bg.content_margin_right = 3
	bg.set_corner_radius_all(3)
	l.add_theme_stylebox_override("normal", bg)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 1)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return l

## A click does the obvious fix with what you carry: best food, drink or bandage.
func _act(act: String) -> void:
	var state: PlayerStateData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	if act in ["food", "drink", "medical"]:
		var pick := best_item(state, act)
		if pick != &"":
			state.ui_use = pick
	elif act == "sleep" or act == "bag":
		_tap(PlayerInputSystem.SLEEP_ACTION if act == "sleep" else PlayerInputSystem.INVENTORY_ACTION)

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)

## The carried item of this kind that restores the most.
static func best_item(state: PlayerStateData, kind: String) -> StringName:
	var stat: String = {"food": "hunger", "drink": "thirst", "medical": "heal"}[kind]
	var best: StringName = &""
	for id in state.inventory:
		var it := ItemCatalog.item(id)
		if it.get("kind", "") == kind and state.inventory[id] > 0 and (best == &"" or it.get(stat, 0.0) > ItemCatalog.item(best).get(stat, 0.0)):
			best = id
	return best
