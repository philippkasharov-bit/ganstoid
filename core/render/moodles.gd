## UI24: moodles exactly the Project Zomboid way. A column of square tiles on
## the right edge, one per state that matters right now and nothing when all
## is well. Bad moodles sit on red, going from pale to deep red over four
## levels; good ones sit on green. The icon is drawn dark on the tile. Each
## level has its own name (Peckish, Hungry, Very Hungry, Starving), shown with
## a line of what it does when you hover. A tile wobbles for a moment when it
## appears or changes level. No numbers, no bars. A click still does the
## obvious fix (eat, drink, bandage, sleep). Reads state; the one write is
## state.ui_use.
class_name Moodles
extends VBoxContainer

const TILE := 38.0
const ICON := 26.0
const BAD := [Color("c98a7c"), Color("c0604f"), Color("a9372b"), Color("7e1b17")]
const GOOD := [Color("8fbf7e"), Color("6fae5b"), Color("4f9440"), Color("357a2a")]
const ICON_INK := Color(0.1, 0.09, 0.09, 0.9)
const WOBBLE_S := 1.2
const REFRESH_S := 0.25

## key: [icon file, field, level names (1..4), what it does, click]
const NEEDS := {
	"hunger": ["hunger", "hunger", ["Peckish", "Hungry", "Very Hungry", "Starving"], "Hunger slows you down, then starts to hurt.", "food"],
	"thirst": ["thirst", "thirst", ["Slightly Thirsty", "Thirsty", "Parched", "Dying of Thirst"], "Thirst hurts sooner than hunger.", "drink"],
	"tired": ["fatigue", "fatigue", ["Drowsy", "Tired", "Very Tired", "Ridiculously Tired"], "Tiredness spoils your aim and your speed. Sleep (Z).", "sleep"],
	"injured": ["health", "health", ["Minor Injury", "Injured", "Severely Injured", "Critically Injured"], "Low health. One more fight could finish you.", "medical"],
	"stress": ["calm", "stress", ["Anxious", "Agitated", "Stressed", "Nervous Wreck"], "Stress spoils your aim and your talk.", ""],
}
const NEED_EDGES := [0.5, 0.7, 0.85, 0.95]
const HURT_EDGES := [0.15, 0.35, 0.6, 0.8]

var _world: World
var _left := 0.0
var _key := ""
var _seen := {}       # moodle family -> level last shown, to wobble on change
var _clock := 0.0
var _tip := UiTooltip.new()

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 4)
	add_child(_tip)
	_tip.top_level = true

## [icon, name shown, level 1-4, good?, description, click] for each moodle on now.
static func list(npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	for key in NEEDS:
		var n: Array = NEEDS[key]
		var lack: float = npc.stress if key == "stress" else 1.0 - float(npc.get(n[1]))
		var lvl := level(lack, HURT_EDGES if key == "injured" else NEED_EDGES)
		if lvl > 0:
			out.append([n[0], n[2][lvl - 1], lvl, false, n[3], n[4]])
	if npc.hunger > 0.95:
		out.append(["well_fed", "Well Fed", 1, true, "You ate well. Nothing to worry about for a while.", ""])
	_problems(out, npc, state)
	return out

static func _problems(out: Array, npc: NPCData, state: PlayerStateData) -> void:
	if npc.bleeding:
		out.append(["bleeding", "Bleeding", 3, false, "You are losing blood. Bandage it now.", "medical"])
	if state.law_tier > 0:
		var lvl := clampi(state.law_tier, 1, 4)
		out.append(["wanted", ["Watched", "Wanted", "Hunted", "Most Wanted"][lvl - 1], lvl, false, "The police are after you. Get out of sight and it cools.", ""])
	if state.case_evidence >= CaseSystem.WARRANT_AT:
		out.append(["warrant", "Warrant", 3, false, "There is a warrant out. Cops arrest on sight.", ""])
	if InventoryWindow.carried_kg(state) > ItemCatalog.CARRY_KG:
		out.append(["heavy", "Heavy Load", 1, false, "You carry too much.", "bag"])

## 0 none, 1..4 by how far past each edge `lack` is.
static func level(lack: float, edges: Array) -> int:
	var lvl := 0
	for edge in edges:
		if lack >= edge:
			lvl += 1
	return lvl

func _process(delta: float) -> void:
	if _world == null:
		return
	_clock += delta
	_wobble()
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH_S
	position = Vector2(get_viewport_rect().size.x - TILE - UiTheme.MARGIN, 66)
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	visible = p != null and GameRules.of(_world) != null
	if not visible:
		return
	var shown := list(p.get_component(ComponentNames.NPC), p.get_component(ComponentNames.PLAYER_STATE))
	var key := str(shown.map(func(m: Array) -> String: return "%s%d" % [m[1], m[2]]))
	if key != _key:
		_key = key
		_rebuild(shown)

func _rebuild(shown: Array) -> void:
	for c in get_children():
		if c != _tip:
			remove_child(c)
			c.queue_free()
	var now := {}
	for m in shown:
		var family: String = m[0] + str(m[3])
		var tile := _tile(m)
		if _seen.get(family, -1) != m[2]:
			tile.set_meta("wobble_until", _clock + WOBBLE_S)   # new or changed: wobble like Zomboid
		now[family] = m[2]
		add_child(tile)
	_seen = now

func _tile(m: Array) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(TILE, TILE)
	var colour: Color = (GOOD if m[3] else BAD)[m[2] - 1]
	var face := UiTheme.box(colour, colour.darkened(0.35), 1)
	face.set_corner_radius_all(6)
	face.border_width_bottom = 2
	for look in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(look, face)
	var art := icon_or_glyph(m[0], m[1].left(1), ICON)
	art.position = Vector2((TILE - ICON) * 0.5, (TILE - ICON) * 0.5 - 1)
	art.modulate = ICON_INK
	b.add_child(art)
	b.pivot_offset = Vector2(TILE, TILE) * 0.5
	b.mouse_entered.connect(func() -> void: _tip.show_at(b.global_position + Vector2(-230, 0), m[1], [[m[4], UiTheme.TEXT]]))
	b.mouse_exited.connect(_tip.hide_tip)
	b.pressed.connect(func() -> void: _act(m[5]))
	return b

func _wobble() -> void:
	for c in get_children():
		if c is Button:
			var left: float = c.get_meta("wobble_until", 0.0) - _clock
			c.rotation = deg_to_rad(9.0 * sin(_clock * 22.0) * clampf(left / WOBBLE_S, 0.0, 1.0)) if left > 0.0 else 0.0

## art/ui/needs/<name>.png, then art/ui/icons/<name>.png, else the letter.
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
	var l := UiTheme.label(glyph, 18, Color.WHITE)
	l.size = Vector2(px, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
