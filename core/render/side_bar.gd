## UI6: Zomboid's left icon strip: one square button per screen, its key
## under it. A click sends that key's action, so the bar never does anything
## the keyboard cannot.
class_name SideBar
extends VBoxContainer

## [label, key shown, input action, icon name]
const BUTTONS := [
	["Bag", "I", &"inventory", "bag"],
	["Character", "K", &"skills_window", "skills"],
	["Crew", "Tab", &"ui_focus_next", "crew"],
	["Turf", "U", &"turf_map", "turf"],
]
const SIZE := Vector2(46, 44)

var _world: World
var _badges: Array[Label] = []
var _left := 0.0

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 3)
	position = Vector2(6, 110)
	for b in BUTTONS:
		add_child(_button(b[0], b[1], b[2], b[3]))

func _button(label: String, key: String, action: StringName, icon: String) -> Button:
	var b := Button.new()
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := Moodles.icon_or_glyph(icon, label.left(1), 28.0)   # UI22: icon on top, text under it, nothing overlaps
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(art)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := UiTheme.label(key, 9, UiTheme.DIM)
	var badge := UiTheme.label("", 9, UiTheme.TEXT)
	for part in [k, badge]:
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(part)
	stack.add_child(line)
	b.add_child(stack)
	_badges.append(badge)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = SIZE
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	b.add_theme_stylebox_override("normal", UiTheme.window_box())
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BG_HEADER, UiTheme.ACCENT))
	b.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.BG_ROW_SELECT, UiTheme.ACCENT))
	b.tooltip_text = "%s (%s)" % [label, key]
	b.pressed.connect(func() -> void: _send(action))
	return b

func _send(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)

## UI8: a number on each button: bag weight, total skill levels, crew, blocks held.
func _process(delta: float) -> void:
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = 0.5
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null or _badges.size() < 4:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var levels := 0
	for s in Skills.NAMES:
		levels += Skills.level(state, s)
	var t := TerritorySystem.data(_world)
	_badges[0].text = "%.1fkg" % InventoryWindow.carried_kg(state)
	_badges[1].text = "Lv%d" % levels
	_badges[2].text = "%d/%d" % [state.crew_ids.size(), CrewSystem.MAX_CREW]
	_badges[3].text = str(TerritorySystem.cells_held(t, TerritorySystem.PLAYER)) if t != null else "-"
