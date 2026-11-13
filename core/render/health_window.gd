## HP1/HP2: the health window (H), Project Zomboid's Health panel: the body
## figure on the left, each of the 17 parts filled by how bad it is, the same
## colour as its line in the injury list on the right. Each line is the part,
## then its wound and what is going on with it (Bleeding, Bandaged, Dirty
## bandage, Infected). Hover a part or a line for what it means and what to do.
## Read-only; bandaging is done from the bag, the moodle, or the right-click menu.
class_name HealthWindow
extends UiWindow

const ACTION := &"health_window"
const STATUS := [[0.9, "Healthy"], [0.7, "Hurt"], [0.45, "Injured"], [0.2, "Severely injured"], [0.0, "Critical"]]

var _world: World
var _doll := BodyDoll.new()
var _overall := UiTheme.label("", UiTheme.FONT_TITLE)
var _list := VBoxContainer.new()
var _tip := UiTooltip.new()
var _key := ""

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("health", "Health", at, Vector2(360, 0))
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	body.add_child(split)
	var left := VBoxContainer.new()
	left.add_child(_doll)
	split.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 196
	right.add_child(_overall)
	right.add_child(UiTheme.divider())
	right.add_child(UiTheme.label("Injuries", UiTheme.FONT_SMALL, UiTheme.DIM))
	_list.add_theme_constant_override("separation", 3)
	right.add_child(_list)
	split.add_child(right)
	add_child(_tip)
	_tip.top_level = true
	_doll.hover_part.connect(_show_part)
	_doll.hover_end.connect(_tip.hide_tip)
	_bind_key()
	visible = false

func _bind_key() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_H
	InputMap.action_add_event(ACTION, ev)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION):
		visible = not visible
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		close_window()
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if not visible or p == null:
		_tip.hide_tip()
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var npc: NPCData = p.get_component(ComponentNames.NPC)
	BodyParts.ensure(state)
	var key := "%s|%d" % [state.body, roundi(npc.health * 100)]
	if key != _key:
		_key = key
		_rebuild(state, npc)

func _rebuild(state: PlayerStateData, npc: NPCData) -> void:
	_doll.body = state.body
	_doll.queue_redraw()
	_overall.text = "%s  %d%%" % [status_word(npc.health), roundi(npc.health * 100)]
	_overall.add_theme_color_override("font_color", BodyDoll.SEVERITY[_overall_severity(npc.health)])
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var parts: Array = BodyParts.PARTS.filter(func(p: String) -> bool: return injury_line(p, state.body[p]) != "")
	parts.sort_custom(func(a: String, b: String) -> bool: return BodyParts.severity(state.body[a]) > BodyParts.severity(state.body[b]))
	for part in parts:
		_list.add_child(_row(part, state.body[part]))
	if parts.is_empty():
		_list.add_child(UiTheme.label("No injuries.", UiTheme.FONT_SMALL, UiTheme.DIM))

## Zomboid's overall line: a word, then the number.
static func status_word(health: float) -> String:
	for s in STATUS:
		if health >= s[0]:
			return s[1]
	return "Critical"

static func _overall_severity(health: float) -> int:
	return 0 if health >= 0.9 else (1 if health >= 0.7 else (2 if health >= 0.45 else 3))

## One injury: a swatch in the part's colour, the part, then its tags.
func _row(part: String, b: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	var sw := ColorRect.new()
	sw.color = BodyDoll.colour_of(b)
	sw.custom_minimum_size = Vector2(8, 8)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(sw)
	top.add_child(UiTheme.label(BodyParts.NAMES[part], UiTheme.FONT_SMALL, UiTheme.TEXT))
	row.add_child(top)
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 6)
	for t in tags_of(b):
		tags.add_child(UiTheme.label(t[0], 10, t[1]))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 13)
	pad.add_child(tags)
	row.add_child(pad)
	row.mouse_entered.connect(func() -> void: _show_part(part, row.global_position + Vector2(row.size.x, 0)))
	row.mouse_exited.connect(_tip.hide_tip)
	return row

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

## What to do about it, in a line (Zomboid's first-aid advice).
static func advice(b: Dictionary) -> String:
	if b["bleeding"]:
		return "Bandage it now: you are losing blood."
	if float(b.get("infection", 0.0)) >= 1.0:
		return "Infected: it won't heal and drains your health. Put a clean bandage on."
	if BodyParts.dirty(b):
		return "The bandage is dirty. Change it before the wound gets infected."
	if b["wound"] == "fracture":
		return "Broken bone: heals slowly. You limp or aim badly until it does."
	if BodyParts.WOUNDS.get(b["wound"], [0, false])[1] and not b["bandaged"]:
		return "Open wound: bandage it or it can get infected."
	return "Heals by itself while you are fed."

func _show_part(part: String, at: Vector2) -> void:
	var state: PlayerStateData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var b: Dictionary = state.body[part]
	var lines: Array = [["Condition %d%%" % roundi(float(b["hp"]) * 100), BodyDoll.colour_of(b) if BodyParts.severity(b) > 0 else UiTheme.GOOD]]
	if injury_line(part, b) == "":
		lines.append(["Fine", UiTheme.TEXT])
	else:
		lines.append_array(tags_of(b))
	_tip.show_at(at, BodyParts.NAMES[part], lines, advice(b) if injury_line(part, b) != "" else "")
