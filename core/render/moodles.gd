## UI9/UI13: DayZ-style status column on the right edge of the screen. Each
## icon fills from the bottom with its number (food 25% = a quarter full) over
## a dark empty silhouette, with ↑/↓ arrows for how fast it moves and the
## number under it. No coloured boxes: just the icons on one thin bar.
## Problems (bleeding, wanted, warrant, heavy) sit on top while they apply;
## only bleeding pulses. Click an icon for the obvious fix; hover explains.
## Reads state; the one write is state.ui_use.
class_name Moodles
extends VBoxContainer

const ICON := 34.0
const CELL := Vector2(48, 62)
const EMPTY := Color(0.0, 0.0, 0.0, 0.5)   # the unfilled part of every icon
const OK := Color(0.93, 0.93, 0.9)
const STATE_COLOURS := [OK, Color("e8c547"), Color("e8913a"), Color("e0533d")]
const REFRESH_S := 0.25
const TREND_S := 1.0                      # real seconds between trend samples
const ARROW_PER_DAY := [0.15, 2.0]   # change per game day for 1 and 2 arrows
const HIT_DROP := 0.05               # health lost in one sample that counts as a fight

## [key (icon file + npc field), name, what a click does, why it matters]
## UI10: each icon keeps its own colour (what it is); how bad it is shows in
## the frame, arrows and number (white fine, then yellow, orange, red).
const IDENTITY := {
	"hunger": Color("e0a050"), "thirst": Color("4fa8e8"), "fatigue": Color("f2d34b"),
	"health": Color("e4574f"), "calm": Color("5cc85a"), "bleeding": Color("ff4a55"),
	"wanted": Color("5a8cf0"), "warrant": Color("e8b35a"), "heavy": Color("a8a8a0"),
}

## UI11/12: food and water icons run red (empty) through yellow to green
## (full); energy runs red to yellow.
const GAUGE := ["hunger", "thirst", "fatigue"]

## Energy runs red (empty) to its own yellow (full), not to green.
static func gauge_colour(v: float, key: String = "hunger") -> Color:
	var red := Color("e0533d")
	var yellow := Color("e8c547")
	if key == "fatigue":
		return red.lerp(Color("f2d34b"), v)
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
var _vignette := TextureRect.new()
var _lost := 0.0

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 0)
	resized.connect(queue_redraw)
	add_child(_tip)
	_tip.top_level = true
	_vignette.texture = _vignette_texture()
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false

## The red edge sits under every panel: first child of the HUD layer.
func _ready() -> void:
	get_parent().add_child.call_deferred(_vignette)
	get_parent().move_child.call_deferred(_vignette, 0)

## The one thin bar behind the column (a box container draws no panel itself).
func _draw() -> void:
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(0.05, 0.05, 0.06, 0.35)
	bar.set_corner_radius_all(8)
	draw_style_box(bar, Rect2(Vector2(-2, -4), size + Vector2(4, 8)))

func _add_glow(cell: Button) -> void:
	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.texture = _glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.size = Vector2(ICON, ICON) * 1.6
	glow.position = Vector2((CELL.x - glow.size.x) * 0.5, 11 + (ICON - glow.size.y) * 0.5)
	glow.pivot_offset = glow.size * 0.5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.show_behind_parent = false
	cell.add_child(glow)
	cell.move_child(glow, 0)   # behind the drop

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

## Conditional problems as [icon key, name, badge, why, act, fill 0..1].
static func notices(npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	if npc.bleeding:
		out.append(["bleeding", "Bleeding", "-%d/m" % roundi(WoundSystem.BLEED_PER_MIN * 100), "Losing %d%% health a minute. Click: apply a bandage." % roundi(WoundSystem.BLEED_PER_MIN * 100), "medical", clampf(0.2 + (1.0 - npc.health) * 0.8, 0.0, 1.0)])   # blood lost; a fresh wound shows a little
	if state.law_tier > 0:
		out.append(["wanted", "Wanted", "%d/4" % state.law_tier, "Heat level %d of 4. Get out of sight and it cools." % state.law_tier, "", state.law_tier / 4.0])
	if state.case_evidence >= CaseSystem.WARRANT_AT:
		out.append(["warrant", "Warrant", str(roundi(state.case_evidence)), "Case %d (warrant at %d). Cops arrest on sight." % [roundi(state.case_evidence), roundi(CaseSystem.WARRANT_AT)], "", clampf(state.case_evidence / (CaseSystem.WARRANT_AT * 2.0), 0.0, 1.0)])
	var kg := InventoryWindow.carried_kg(state)
	if kg > ItemCatalog.CARRY_KG:
		out.append(["heavy", "Heavy load", "%.0fkg" % kg, "%.1f of %.0f kg. Click: open the bag." % [kg, ItemCatalog.CARRY_KG], "bag", clampf(kg / (ItemCatalog.CARRY_KG * 1.5), 0.0, 1.0)])
	return out

## UI14: arrows from a change per game day: ↓ normal drain, ↓↓ fast (a meal,
## sleep, a wound), ↓↓↓ only in a critical moment (a fight, bleeding, or the
## need nearly empty). Positive up, negative down.
static func arrows(per_day: float, critical: bool = false) -> int:
	var n := 0
	for edge in ARROW_PER_DAY:
		if absf(per_day) >= edge:
			n += 1
	if n == 2 and critical:
		n = 3
	return n if per_day > 0.0 else -n

func _process(delta: float) -> void:
	if _world == null:
		return
	_pulse += delta
	_left -= delta
	_trend_left -= delta
	var screen := get_viewport_rect().size
	position = Vector2(screen.x - size.x - 8, (screen.y - size.y) * 0.5)
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
			var hit: bool = need[0] == "health" and _before[need[0]] - now >= HIT_DROP
			var critical: bool = hit or now < 0.15 or (need[0] == "health" and npc.bleeding)
			_trend[need[0]] = arrows((now - _before[need[0]]) / ticks * SimClock.day_ticks, critical)
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
		var cell := _cell(n[0], n[1], 3, "", n[2], n[3], n[4], n[5])
		if n[0] == "bleeding":
			cell.set_meta("pulse", true)
			_add_glow(cell)
			_lost = 1.0 - npc.health
		add_child(cell)
	for need in NEEDS:
		var v := value(npc, need[0])
		var t: int = _trend.get(need[0], 0)
		var why := "%d%% %s. %s" % [roundi(v * 100), "rising" if t > 0 else ("falling" if t < 0 else "steady"), need[3]]
		add_child(_cell(need[0], need[1], level_of(v), ("↑" if t > 0 else "↓").repeat(absi(t)), "%d%%" % roundi(v * 100), why, need[2], v, gauge_colour(v, need[0]) if need[0] in GAUGE else Color.TRANSPARENT))

func _cell(icon: String, name: String, level: int, arrow_text: String, number: String, why: String, act: String, fill: float, tint: Color = Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.flat = true   # no box: just the icon
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CELL
	b.set_meta("level", level)
	var col: Color = tint if tint.a > 0.0 else IDENTITY.get(icon, UiTheme.TEXT)
	var arrow := UiTheme.label(arrow_text, 10, STATE_COLOURS[level])
	arrow.size = Vector2(CELL.x, 11)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var art := _filled(icon, fill, col)
	art.name = "Art"
	art.position = Vector2((CELL.x - ICON) * 0.5, 11)
	var num := UiTheme.label(number, 11, col.lightened(0.25))
	num.position = Vector2(0, 11 + ICON)
	num.size = Vector2(CELL.x, 13)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for part in [arrow, art, num]:
		_shadow(part)
		b.add_child(part)
	b.mouse_entered.connect(func() -> void: _tip.show_at(b.global_position + Vector2(-270, 0), "%s  (%s)" % [name, ["fine", "low", "very low", "critical"][level]], [[why, UiTheme.TEXT]]))
	b.mouse_exited.connect(_tip.hide_tip)
	b.pressed.connect(func() -> void: _act(act))
	return b

static func _shadow(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if c is Label:
		c.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		c.add_theme_constant_override("outline_size", 4)

## UI15: bleeding beats like a heart (lub-dub, about 80 bpm): the drop pops
## and glows on each beat and the screen edges flush red, stronger the more
## blood is lost. Nothing else animates, so the eye goes straight to it.
const BEAT_S := 0.75

static func heartbeat(t: float) -> float:
	var p := fmod(t, BEAT_S) / BEAT_S
	return maxf(exp(-pow(p / 0.07, 2.0)), 0.65 * exp(-pow((p - 0.28) / 0.07, 2.0)))

func _blink() -> void:
	var beat := heartbeat(_pulse)
	var bleeding := false
	for c in get_children():
		if c is Button and c.get_meta("pulse", false):
			bleeding = true
			var art: Control = c.get_node("Art")
			art.pivot_offset = art.size * 0.5
			art.scale = Vector2.ONE * (1.0 + 0.22 * beat)
			var glow: Control = c.get_node("Glow")
			glow.modulate.a = 0.25 + 0.75 * beat
			glow.scale = Vector2.ONE * (0.8 + 0.4 * beat)
	_vignette.visible = bleeding
	if bleeding:
		_vignette.size = get_viewport_rect().size
		_vignette.modulate.a = (0.15 + 0.85 * beat) * clampf(0.2 + _lost * 0.7, 0.0, 0.9)

static func _glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.15, 0.2, 0.9))
	g.set_color(1, Color(1.0, 0.1, 0.15, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex

## Clear in the middle, blood red at the edges.
static func _vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.6, 0.0, 0.03, 0.0), Color(0.6, 0.0, 0.03, 0.0), Color(0.6, 0.0, 0.04, 0.7)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

## UI13: an icon filled from the bottom to `fill`: the dark empty silhouette
## behind, the coloured part clipped to the filled share.
static func _filled(icon: String, fill: float, colour: Color) -> Control:
	var holder := Control.new()
	holder.size = Vector2(ICON, ICON)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var empty := icon_or_glyph(icon, icon.left(1).to_upper(), ICON)
	empty.modulate = EMPTY
	holder.add_child(empty)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := ICON * clampf(fill, 0.0, 1.0)
	clip.position = Vector2(0, ICON - h)
	clip.size = Vector2(ICON, h)
	var full := icon_or_glyph(icon, icon.left(1).to_upper(), ICON)
	full.modulate = colour
	full.position = Vector2(0, -(ICON - h))
	clip.add_child(full)
	holder.add_child(clip)
	return holder

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
