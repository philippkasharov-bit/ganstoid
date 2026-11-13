## UI24: moodles exactly the Project Zomboid way. A column of square tiles on
## the right edge, one per state that matters right now and nothing when all
## is well. Bad moodles sit on red, going from pale to deep red over four
## levels; good ones sit on green. The icon is drawn dark on the tile. Each
## level has its own name (Peckish, Hungry, Very Hungry, Starving), shown with
## a line of what it does when you hover (with the number behind it). A tile
## slides in, shakes when it gets worse, shows an arrow when it changes and
## slides out when it clears (A1/A2). The column itself never moves. A click still does the
## obvious fix (eat, drink, bandage, sleep). Reads state; the one write is
## state.ui_use.
class_name Moodles
extends VBoxContainer

const TILE := 30.0   # MD2: Zomboid-small
const ICON := 20.0
const BAD := [Color("c98a7c"), Color("c0604f"), Color("a9372b"), Color("7e1b17")]
const GOOD := [Color("8fbf7e"), Color("6fae5b"), Color("4f9440"), Color("357a2a")]
const ICON_INK := Color(0.1, 0.09, 0.09, 0.9)
const CLICK_TEXT := {"food": "eat the best food you carry", "drink": "drink", "medical": "bandage the worst wound", "sleep": "sleep", "bag": "open the bag"}
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
const VALUE_NAMES := {"hunger": "Food %d%%", "thirst": "Water %d%%", "tired": "Energy %d%%", "injured": "Health %d%%", "stress": "Stress %d%%"}
const HURT_EDGES := [0.15, 0.35, 0.6, 0.8]

var _world: World
var _left := 0.0
var _key := ""
var _seen := {}       # moodle family -> level last shown, to flash on change
var below: Control    # the clock: the column starts under it
var _clock := 0.0
var _tip := UiTooltip.new()

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 4)
	add_child(_tip)
	_tip.top_level = true

## [icon, name shown, level 1-4, good?, description, click, value] for each
## moodle on now; value is the number behind it ("Food 38%"), for the hover card.
static func list(npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	for key in NEEDS:
		var n: Array = NEEDS[key]
		var lack: float = npc.stress if key == "stress" else 1.0 - float(npc.get(n[1]))
		var lvl := level(lack, HURT_EDGES if key == "injured" else NEED_EDGES)
		if lvl > 0:
			out.append([n[0], n[2][lvl - 1], lvl, false, n[3], n[4], VALUE_NAMES[key] % roundi((lack if key == "stress" else 1.0 - lack) * 100)])
	if npc.hunger > 0.95:
		out.append(["well_fed", "Well Fed", 1, true, "You ate well. Nothing to worry about for a while.", "", "Food %d%%" % roundi(npc.hunger * 100)])
	_problems(out, npc, state)
	return out

static func _problems(out: Array, npc: NPCData, state: PlayerStateData) -> void:
	if npc.bleeding:
		out.append(["bleeding", "Bleeding", 3, false, "You are losing blood. Bandage it now.", "medical", "Health %d%% and falling" % roundi(npc.health * 100)])
	if state.law_tier > 0:
		var lvl := clampi(state.law_tier, 1, 4)
		out.append(["wanted", ["Watched", "Wanted", "Hunted", "Most Wanted"][lvl - 1], lvl, false, "The police are after you. Get out of sight and it cools.", "", "Heat %d / 4" % lvl])
	if state.case_evidence >= CaseSystem.WARRANT_AT:
		out.append(["warrant", "Warrant", 3, false, "There is a warrant out. Cops arrest on sight.", "", "Case %d" % roundi(state.case_evidence)])
	if InventoryWindow.carried_kg(state) > ItemCatalog.CARRY_KG:
		out.append(["heavy", "Heavy Load", 1, false, "You carry too much.", "bag", "%.1f / %.0f kg" % [InventoryWindow.carried_kg(state), ItemCatalog.CARRY_KG]])

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
	_flash()
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH_S
	var top := below.position.y + below.size.y + UiTheme.SPACE if below != null and below.visible else 66.0
	position = Vector2(get_viewport_rect().size.x - TILE - UiTheme.MARGIN, top).round()
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	visible = p != null and GameRules.of(_world) != null
	if not visible:
		return
	var shown := list(p.get_component(ComponentNames.NPC), p.get_component(ComponentNames.PLAYER_STATE))
	var key := str(shown.map(func(m: Array) -> String: return "%s%d" % [m[1], m[2]]))
	if key != _key:
		_key = key
		_rebuild(shown)

## A1/A2: every change shows what happened. A new moodle slides in from the
## right; one that gets worse shakes and shows a red down arrow; one that gets
## better shows a green up arrow; one that goes away slides out with its
## arrow (up when a bad one clears). Tiles sit in a wrapper so the column
## stays put while the face moves.
const SLIDE_S := 0.35
const ARROW_S := 1.6
var _last_rows := {}   # moodle family -> its last row, for the slide-out
var _anims := {}       # moodle family -> [anim, start], so a rebuild for another tile does not cut it short

func _rebuild(shown: Array) -> void:
	for c in get_children():
		if c != _tip and not c.has_meta("ghost"):
			remove_child(c)
			c.queue_free()
	var now := {}
	var rows := {}
	for m in shown:
		var family: String = m[0] + str(m[3])
		var before: int = _seen.get(family, -1)
		var anim := "in" if before < 0 else ("worse" if m[2] > before else ("better" if m[2] < before else ""))
		var t0 := _clock
		if anim == "" and _anims.has(family) and _clock - float(_anims[family][1]) < ARROW_S:
			anim = _anims[family][0]   # still showing its arrow from a moment ago
			t0 = _anims[family][1]
		if anim != "":
			_anims[family] = [anim, t0]
		add_child(_wrap(m, anim, t0))
		now[family] = m[2]
		rows[family] = m
	for family in _seen:
		if not now.has(family) and _last_rows.has(family):
			var ghost := _wrap(_last_rows[family], "out", _clock)
			ghost.set_meta("ghost", true)
			add_child(ghost)
	_seen = now
	_last_rows = rows

func _wrap(m: Array, anim: String, t0: float) -> Control:
	var w := Control.new()
	w.custom_minimum_size = Vector2(TILE, TILE)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := _tile(m)
	face.size = Vector2(TILE, TILE)
	w.add_child(face)
	if anim != "":
		w.set_meta("anim", anim)
		w.set_meta("t0", t0)
		var up: bool = anim == "better" or (anim == "out" and not m[3])
		if anim != "in":
			w.add_child(_arrow(up))
		if anim == "in" and _clock - t0 < 0.01:
			face.position.x = TILE * 1.3
	return w

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
	art.position = ((Vector2(TILE, TILE - 2) - Vector2(ICON, ICON)) * 0.5).round()   # centred above the 2px base
	art.modulate = ICON_INK
	b.add_child(art)
	var lines: Array = [[m[6], BAD[3].lightened(0.4) if not m[3] else GOOD[1]], [m[4], UiTheme.TEXT]]
	if m[5] != "":
		lines.append(["Click: " + CLICK_TEXT.get(m[5], m[5]), UiTheme.DIM])
	b.mouse_entered.connect(func() -> void: _tip.show_at(b.global_position, m[1], lines))   # no room on the right: it flips to the left of the column
	b.mouse_exited.connect(_tip.hide_tip)
	b.pressed.connect(func() -> void: _act(m[5]))
	return b

## The small arrow left of a tile: green up when it got better, red down when worse.
func _arrow(up: bool) -> Control:
	var a := Control.new()
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.position = Vector2(-12, TILE * 0.5)
	a.draw.connect(func() -> void:
		var col := UiTheme.GOOD if up else UiTheme.BAD
		var d := -1.0 if up else 1.0   # an arrow 8 px wide, 12 px tall, with a dark edge so it reads on any ground
		var head := PackedVector2Array([Vector2(0, 7 * d), Vector2(-5, 0), Vector2(5, 0)])
		var shaft := Rect2(Vector2(-2, -6 if not up else 0), Vector2(4, 6))
		a.draw_colored_polygon(head, Color(0, 0, 0, 0.6))
		a.draw_rect(shaft.grow(1), Color(0, 0, 0, 0.6))
		a.draw_rect(shaft, col)
		a.draw_colored_polygon(PackedVector2Array([head[0] * 0.8, head[1] * 0.8, head[2] * 0.8]), col))
	return a

func _flash() -> void:
	for w in get_children():
		if not w.has_meta("anim"):
			continue
		var t: float = _clock - float(w.get_meta("t0"))
		var face: Control = w.get_child(0)
		match String(w.get_meta("anim")):
			"in":
				face.position.x = TILE * 1.3 * (1.0 - ease(clampf(t / SLIDE_S, 0.0, 1.0), 0.3))
			"worse":
				face.position.x = 3.0 * sin(t * 40.0) * clampf(1.0 - t / 0.5, 0.0, 1.0)
			"out":
				face.position.x = TILE * 1.3 * ease(clampf(t / 0.5, 0.0, 1.0), 2.0)
				w.modulate.a = clampf(1.0 - t / 0.6, 0.0, 1.0)
				if t > 0.6:
					w.queue_free()
		if w.get_child_count() > 1:
			var arrow: Control = w.get_child(1)
			arrow.visible = t < ARROW_S
			arrow.position.y = TILE * 0.5 + 2.0 * sin(t * 8.0)
			arrow.queue_redraw()
		if t > ARROW_S and w.get_meta("anim") != "out":
			face.position.x = 0.0
			w.remove_meta("anim")

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
