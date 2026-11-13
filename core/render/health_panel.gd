## HP1-HP3/CI1: the Health tab of the Character Info window, Project
## Zomboid's Health panel. Left: the body figure, each of the 17 parts filled
## by how bad it is. Right: the injury list in the same colours, and under it
## the card of the part you picked (click a part or a line): condition,
## wound, bleeding, bandage, infection, how long it takes to heal and what it
## does to you, with its treatment buttons. Right-click a part or a line for
## the same treatments as a menu, Zomboid's way. The one write is state.ui_treat.
class_name HealthPanel
extends VBoxContainer

const STATUS := [[0.9, "Healthy"], [0.7, "Hurt"], [0.45, "Injured"], [0.2, "Severely injured"], [0.0, "Critical"]]
const CARD_W := 210.0

var _world: World
var _doll := BodyDoll.new()
var _overall := UiTheme.label("", UiTheme.FONT_TITLE)
var _list := VBoxContainer.new()
var _card := VBoxContainer.new()
var _menu := ContextMenu.new()
var _menu_ops: Array = []
var _selected := ""
var _key := ""
var _hurt_seen := -1

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", UiTheme.SPACE)
	add_child(_overall)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	add_child(split)
	split.add_child(_doll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = CARD_W
	right.add_theme_constant_override("separation", UiTheme.GAP)
	_list.add_theme_constant_override("separation", 0)
	right.add_child(_list)
	right.add_child(UiTheme.divider())
	_card.add_theme_constant_override("separation", 2)
	right.add_child(_card)
	split.add_child(right)
	add_child(_menu)
	_menu.top_level = true
	_menu.picked.connect(_on_menu)
	_doll.part_clicked.connect(_select)
	_doll.part_menu.connect(_open_menu)

## Esc closes the treatment menu first. True if it did.
func close_menu() -> bool:
	if not _menu.visible:
		return false
	_menu.visible = false
	return true

## Called by the window while this tab shows.
func refresh() -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var npc: NPCData = p.get_component(ComponentNames.NPC)
	BodyParts.ensure(state)
	if state.hurt_serial != _hurt_seen:   # A3: show where the last hit landed
		if _hurt_seen >= 0 and state.hurt_part != "":
			_doll.blink(state.hurt_part)
			_selected = state.hurt_part
		_hurt_seen = state.hurt_serial
	var key := "%s|%d|%s|%d" % [state.body, roundi(npc.health * 100), _selected, state.inventory.get(&"bandage", 0)]
	if key != _key:
		_key = key
		_rebuild(state, npc)

func _rebuild(state: PlayerStateData, npc: NPCData) -> void:
	var hurt := injured_parts(state)
	if _selected == "" or not state.body.has(_selected):
		_selected = hurt[0] if not hurt.is_empty() else "torso_upper"
	_doll.body = state.body
	_doll.selected = _selected
	_doll.queue_redraw()
	_overall.text = "%s  %d%%" % [status_word(npc.health), roundi(npc.health * 100)]
	_overall.add_theme_color_override("font_color", BodyDoll.SEVERITY[_overall_severity(npc.health)])
	_clear(_list)
	for part in hurt:
		_list.add_child(_row(part, state.body[part]))
	if hurt.is_empty():
		_list.add_child(UiTheme.label("No injuries.", UiTheme.FONT_SMALL, UiTheme.DIM))
	_fill_card(state, _selected)

## Hurt parts, worst first.
static func injured_parts(state: PlayerStateData) -> Array:
	var out: Array = BodyParts.PARTS.filter(func(p: String) -> bool: return injury_line(p, state.body[p]) != "")
	out.sort_custom(func(a: String, b: String) -> bool: return BodyParts.severity(state.body[a]) > BodyParts.severity(state.body[b]))
	return out

static func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

## Zomboid's overall line: a word, then the number.
static func status_word(health: float) -> String:
	for s in STATUS:
		if health >= s[0]:
			return s[1]
	return "Critical"

static func _overall_severity(health: float) -> int:
	return 0 if health >= 0.9 else (1 if health >= 0.7 else (2 if health >= 0.45 else 3))

## One line of the list: swatch, part, its tags. Click picks, right-click treats.
func _row(part: String, b: Dictionary) -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = UiTheme.ROW_H
	btn.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BG_ROW_HOVER, Color.TRANSPARENT, 0))
	if part == _selected:
		btn.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.BG_ROW_SELECT, Color.TRANSPARENT, 0))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw := ColorRect.new()
	sw.color = BodyDoll.colour_of(b)
	sw.custom_minimum_size = Vector2(8, 8)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(sw)
	var name_label := UiTheme.label(BodyParts.NAMES[part], UiTheme.FONT_SMALL, UiTheme.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var first: Array = tags_of(b)[0]
	line.add_child(UiTheme.label(first[0], 10, first[1]))
	for c in line.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(line)
	btn.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_select(part)
			_open_menu(part, get_global_mouse_position()))
	btn.pressed.connect(func() -> void: _select(part))
	return btn

func _select(part: String) -> void:
	_selected = part
	_key = ""

## The picked part's card: Zomboid's numbers, then what you can do.
func _fill_card(state: PlayerStateData, part: String) -> void:
	_clear(_card)
	var b: Dictionary = state.body[part]
	_card.add_child(UiTheme.label(BodyParts.NAMES[part], UiTheme.FONT_BODY, UiTheme.ACCENT))
	_card.add_child(_bar(float(b["hp"]), BodyDoll.colour_of(b) if BodyParts.severity(b) > 0 else UiTheme.GOOD))
	for r in card_rows(part, b):
		_card.add_child(_stat(r[0], r[1], r[2]))
	var ops := treatments(state, part)
	if ops.is_empty():
		return
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UiTheme.GAP)
	for op in ops:
		var bt := Button.new()
		bt.text = op["text"]
		bt.disabled = not op["enabled"]
		bt.tooltip_text = op.get("why", "")
		bt.focus_mode = Control.FOCUS_NONE
		bt.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		for look in ["normal", "hover", "pressed", "disabled"]:
			bt.add_theme_stylebox_override(look, UiTheme.button_box(look))
		bt.pressed.connect(func() -> void: _do(op["op"], part))
		buttons.add_child(bt)
	_card.add_child(buttons)

## [label, value, colour] for the card.
static func card_rows(part: String, b: Dictionary) -> Array:
	var wound: String = String(b["wound"]).capitalize() if b["wound"] != "" else ("Sore" if float(b["hp"]) < 0.95 else "None")
	var rows: Array = [["Condition", "%d%%" % roundi(float(b["hp"]) * 100), UiTheme.TEXT],
		["Wound", wound, BodyDoll.colour_of(b) if b["wound"] != "" else UiTheme.TEXT],
		["Bleeding", "Yes" if b["bleeding"] else "No", BodyDoll.SEVERITY[3] if b["bleeding"] else UiTheme.DIM]]
	var bandage := "None"
	if b["bandaged"]:
		bandage = "Dirty" if BodyParts.dirty(b) else "Clean (%dh)" % roundi(float(b["bandage_age"]) * 24.0)
	rows.append(["Bandage", bandage, BodyDoll.SEVERITY[1] if BodyParts.dirty(b) else UiTheme.TEXT])
	var inf := float(b.get("infection", 0.0))
	var pct := roundi(inf * 100)
	rows.append(["Infection", "Infected" if inf >= 1.0 else ("%d%%" % pct if pct > 0 else "None"),
		BodyDoll.INFECTED if inf >= 1.0 else (BodyDoll.SEVERITY[1] if pct > 0 else UiTheme.DIM)])
	var days := BodyParts.heal_days(b)
	var heals := "Not healing" if days < 0.0 else ("Healed" if days <= 0.0 else ("~%dh" % ceili(days * 24.0) if days < 1.0 else "~%.1f days" % days))
	rows.append(["Heals in", heals, BodyDoll.SEVERITY[3] if days < 0.0 else UiTheme.TEXT])
	var fx := BodyParts.effect(part, b)
	if fx != "":
		rows.append(["Effect", fx, BodyDoll.SEVERITY[2]])
	return rows

func _stat(label: String, value: String, colour: Color) -> Control:
	var row := HBoxContainer.new()
	var l := UiTheme.label(label, UiTheme.FONT_SMALL, UiTheme.DIM)
	l.custom_minimum_size.x = 70
	row.add_child(l)
	row.add_child(UiTheme.label(value, UiTheme.FONT_SMALL, colour))
	return row

func _bar(f: float, colour: Color) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(CARD_W, 5)
	bar.draw.connect(func() -> void:
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(1, 1, 1, 0.08))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * clampf(f, 0.0, 1.0), bar.size.y)), colour))
	return bar

## What can be done to a part now: {op, text, enabled, why}.
static func treatments(state: PlayerStateData, part: String) -> Array:
	var b: Dictionary = state.body[part]
	var out: Array = []
	var have := Moodles.best_item(state, "medical") != &""
	if BodyParts.needs_dressing(b):
		var n := int(state.inventory.get(&"bandage", 0))
		out.append({"op": "bandage", "text": "Change bandage" if b["bandaged"] else "Bandage (%d)" % n, "enabled": have, "why": "no bandages"})
	if b["bandaged"]:
		out.append({"op": "remove", "text": "Remove bandage", "enabled": true})
	return out

func _open_menu(part: String, at: Vector2) -> void:
	_select(part)
	var state := _state()
	_menu_ops = treatments(state, part)
	if _menu_ops.is_empty():
		_menu_ops = [{"op": "", "text": "Nothing to treat", "enabled": false, "why": "fine"}]
	_menu.open_at(at, _menu_ops)

func _on_menu(index: int) -> void:
	_menu.visible = false
	if index < _menu_ops.size() and _menu_ops[index]["op"] != "":
		_do(_menu_ops[index]["op"], _selected)

func _do(op: String, part: String) -> void:
	_state().ui_treat = {"op": op, "part": part}

func _state() -> PlayerStateData:
	return _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)

## [text, colour] for each thing wrong with a part, worst first.
static func tags_of(b: Dictionary) -> Array:
	var out: Array = []
	var sev := BodyParts.severity(b)
	out.append([String(b["wound"]).capitalize() if b["wound"] != "" else "Sore", BodyDoll.SEVERITY[maxi(sev, 1)]])
	if b["bleeding"]:
		out.append(["Bleeding", BodyDoll.SEVERITY[3]])
	if float(b.get("infection", 0.0)) >= 1.0:
		out.append(["Infected", BodyDoll.INFECTED])
	if b["bandaged"]:
		out.append(["Dirty bandage" if BodyParts.dirty(b) else "Bandaged", BodyDoll.SEVERITY[1] if BodyParts.dirty(b) else UiTheme.TEXT])
	return out

## "Left thigh: fracture, bleeding" or "" when the part is fine.
static func injury_line(part: String, b: Dictionary) -> String:
	if b["wound"] == "" and float(b["hp"]) >= 0.95:
		return ""
	return "%s: %s" % [BodyParts.NAMES[part], ", ".join(tags_of(b).map(func(t: Array) -> String: return String(t[0]).to_lower()))]
