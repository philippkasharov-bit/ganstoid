## UI6: Zomboid-style moodles: a column of square icons down the right edge,
## one per problem, coloured by how bad it is (1 mild .. 4 critical). Hover
## for what it means. Read-only: derives everything from the player's state.
class_name Moodles
extends VBoxContainer

const SIZE := 52.0
const LEVEL_COLOURS := [Color("8a7a3a"), Color("a3632b"), Color("a83a2c"), Color("7d1420")]
const REFRESH_S := 0.25
const NEED_EDGES := [0.5, 0.7, 0.85, 0.95]
const HURT_EDGES := [0.15, 0.35, 0.6, 0.8]   # wounds matter sooner than an empty stomach

var _world: World
var _left := 0.0
var _key := ""
var _tip := UiTooltip.new()

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 6)
	add_child(_tip)
	_tip.top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(get_viewport_rect().size.x - SIZE - 14, 70)

## One dict per moodle showing now: glyph, name, level 1-4, why, value (the
## number on the badge), act (what a click does: an item kind to use, "sleep",
## "bag" or "" for nothing).
static func list(world: World, npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	_need(out, ["H", "Hungry", "Click: eat the most filling food you carry.", "food"], 1.0 - npc.hunger, npc.hunger)
	_need(out, ["W", "Thirsty", "Click: drink the best drink you carry.", "drink"], 1.0 - npc.thirst, npc.thirst)
	_need(out, ["Z", "Tired", "Click: sleep here (Z). Sleep somewhere safe.", "sleep"], 1.0 - npc.fatigue, npc.fatigue)
	_need(out, ["+", "Hurt", "Click: apply a bandage. Lie low to heal.", "medical"], 1.0 - npc.health, npc.health, HURT_EDGES)
	_need(out, ["S", "Stressed", "Stress spoils aim and talk. Rest and stay out of trouble.", ""], npc.stress, 1.0 - npc.stress)
	if npc.bleeding:
		out.append(_moodle("B", "Bleeding", 4, "Losing %d%% health a minute. Click: apply a bandage." % roundi(WoundSystem.BLEED_PER_MIN * 100), "-%d/m" % roundi(WoundSystem.BLEED_PER_MIN * 100), "medical"))
	if state.law_tier > 0:
		out.append(_moodle("!", "Wanted", clampi(state.law_tier, 1, 4), "Heat level %d of 4. Get out of sight and it cools." % state.law_tier, "%d/4" % state.law_tier, ""))
	if state.case_evidence >= CaseSystem.WARRANT_AT:
		out.append(_moodle("C", "Warrant", 3, "Case %d (warrant at %d). Cops arrest on sight." % [roundi(state.case_evidence), roundi(CaseSystem.WARRANT_AT)], str(roundi(state.case_evidence)), ""))
	var kg := InventoryWindow.carried_kg(state)
	if kg > ItemCatalog.CARRY_KG:
		out.append(_moodle("K", "Heavy load", 1, "%.1f of %.0f kg. Click: open the bag." % [kg, ItemCatalog.CARRY_KG], "%.0fkg" % kg, "bag"))
	return out

static func _moodle(glyph: String, name: String, level: int, why: String, value: String, act: String) -> Dictionary:
	return {"glyph": glyph, "name": name, "level": level, "why": why, "value": value, "act": act}

## Needs read as 0 fine .. 1 empty; Zomboid shows them from about half way.
## The badge shows what is left (food 38%), the tooltip says what a click does.
static func _need(out: Array, info: Array, lack: float, left: float, edges: Array = NEED_EDGES) -> void:
	var lvl := 0
	for edge in edges:
		if lack >= edge:
			lvl += 1
	if lvl > 0:
		out.append(_moodle(info[0], info[1], lvl, "%d%% left. %s" % [roundi(left * 100), info[2]], "%d%%" % roundi(left * 100), info[3]))

func _process(delta: float) -> void:
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = REFRESH_S
	position.x = get_viewport_rect().size.x - SIZE - 14
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null or GameRules.of(_world) == null:
		visible = false
		return
	visible = true
	var shown := list(_world, p.get_component(ComponentNames.NPC), p.get_component(ComponentNames.PLAYER_STATE))
	var key := str(shown.map(func(m: Dictionary) -> String: return m["name"] + str(m["level"]) + m["value"]))
	if key != _key:
		_key = key
		_rebuild(shown)

func _rebuild(shown: Array) -> void:
	for c in get_children():
		if c != _tip:
			remove_child(c)
			c.queue_free()
	for m in shown:
		add_child(_icon(m))

func _icon(m: Dictionary) -> Control:
	var box := Button.new()
	box.focus_mode = Control.FOCUS_NONE
	box.custom_minimum_size = Vector2(SIZE, SIZE)
	var frame := UiTheme.box(Color(0.1, 0.1, 0.11, 0.95), LEVEL_COLOURS[m["level"] - 1].lightened(0.15), 3)
	frame.set_corner_radius_all(6)
	for look in ["normal", "pressed"]:
		box.add_theme_stylebox_override(look, frame)
	var hover := frame.duplicate()
	hover.border_color = UiTheme.ACCENT
	box.add_theme_stylebox_override("hover", hover)
	var art := icon_or_glyph(String(m["name"]).split(" ")[0].to_lower(), m["glyph"], SIZE - 8.0)
	art.position = Vector2(4, 4)
	box.add_child(art)
	box.add_child(badge(m["value"], LEVEL_COLOURS[m["level"] - 1]))
	box.mouse_entered.connect(func() -> void: _show_tip(box, m))
	box.mouse_exited.connect(_tip.hide_tip)
	box.pressed.connect(func() -> void: _act(m["act"]))
	return box

## UI8: the small number in a corner of an icon (Zomboid shows the figure, not just the picture).
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

func _show_tip(box: Control, m: Dictionary) -> void:
	var where := box.global_position + Vector2(-250, 0)
	_tip.show_at(where, "%s  (%s)" % [m["name"], ["mild", "moderate", "severe", "critical"][m["level"] - 1]], [[m["why"], UiTheme.TEXT]])

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

## UI7: art/ui/icons/<name>.png when present, else the letter (art swap point).
static func icon_or_glyph(name: String, glyph: String, px: float) -> Control:
	var path := "res://art/ui/icons/%s.png" % name
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(px, px)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tex
	var l := UiTheme.label(glyph, 22, Color(1, 1, 1, 0.92))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l
