## HP1: the health window (H), Zomboid-style: the body figure on the left,
## coloured part by part, and on the right overall health and the list of
## injuries ("Left arm: cut, bleeding"). Hover a part for its line. Read-only;
## bandaging is done from the bag, the moodle, or the right-click menu.
class_name HealthWindow
extends UiWindow

const ACTION := &"health_window"

var _world: World
var _doll := BodyDoll.new()
var _overall := UiTheme.label("", UiTheme.FONT_BODY)
var _list := VBoxContainer.new()
var _tip := UiTooltip.new()
var _key := ""

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("health", "Health", at, Vector2(320, 0))
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	body.add_child(split)
	split.add_child(_doll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 170
	right.add_child(_overall)
	right.add_child(UiTheme.divider())
	right.add_child(UiTheme.label("Injuries", UiTheme.FONT_SMALL, UiTheme.DIM))
	_list.add_theme_constant_override("separation", 2)
	right.add_child(_list)
	split.add_child(right)
	body.add_child(UiTheme.label("H / Esc close", UiTheme.FONT_SMALL, UiTheme.DIM))
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
	_overall.text = "Overall health  %d%%" % roundi(npc.health * 100)
	_overall.add_theme_color_override("font_color", BodyDoll.condition_colour(npc.health))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for part in BodyParts.PARTS:
		var line := injury_line(part, state.body[part])
		if line != "":
			_list.add_child(UiTheme.label(line, UiTheme.FONT_SMALL, BodyDoll.condition_colour(float(state.body[part]["hp"]))))
	if _list.get_child_count() == 0:
		_list.add_child(UiTheme.label("No injuries.", UiTheme.FONT_SMALL, UiTheme.DIM))

## "Left arm: cut, bleeding" or "" when the part is fine.
static func injury_line(part: String, b: Dictionary) -> String:
	if b["wound"] == "" and float(b["hp"]) >= 0.95:
		return ""
	var bits: PackedStringArray = [b["wound"] if b["wound"] != "" else "sore"]
	if b["bleeding"]:
		bits.append("bleeding")
	if b["bandaged"]:
		bits.append("bandaged")
	return "%s: %s" % [BodyParts.NAMES[part], ", ".join(bits)]

func _show_part(part: String, at: Vector2) -> void:
	var state: PlayerStateData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var b: Dictionary = state.body[part]
	var line := injury_line(part, b)
	_tip.show_at(at, BodyParts.NAMES[part], [["Condition %d%%" % roundi(float(b["hp"]) * 100), BodyDoll.condition_colour(float(b["hp"]))],
		[line.split(": ")[1] if line != "" else "Fine", UiTheme.TEXT]])
