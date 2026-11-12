## UI6: skills (K), Zomboid-style: each skill a name and ten level boxes,
## the next box filling as XP comes in. Read-only.
class_name SkillsWindow
extends UiWindow

const ACTION := &"skills_window"
const BOX := Vector2(18, 14)

var _world: World
var _rows := VBoxContainer.new()
var _key := ""

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("skills", "Skills", at, Vector2(380, 0))
	_rows.add_theme_constant_override("separation", 8)
	body.add_child(_rows)
	body.add_child(UiTheme.label("You learn by doing.    K / Esc close", UiTheme.FONT_SMALL, UiTheme.DIM))
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_K
		InputMap.action_add_event(ACTION, ev)
	visible = false

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION):
		visible = not visible
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		close_window()
	if not visible or _world == null:
		return
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var key := str(state.skills)
	if key != _key:
		_key = key
		_rebuild(state)

func _rebuild(state: PlayerStateData) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for s in Skills.NAMES:
		_rows.add_child(_skill_row(String(s).capitalize(), state.skills.get(s, 0.0)))

## Level n starts at 25 n^2 XP; the box after the last full one shows progress.
func _skill_row(name: String, xp: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var title := UiTheme.label(name)
	title.custom_minimum_size.x = 110
	row.add_child(title)
	var lvl := mini(Skills.MAX_LEVEL, int(sqrt(xp / Skills.XP_PER_LEVEL_SQ)))
	var lo := Skills.XP_PER_LEVEL_SQ * lvl * lvl
	var hi := Skills.XP_PER_LEVEL_SQ * (lvl + 1) * (lvl + 1)
	for i in Skills.MAX_LEVEL:
		var fill := 1.0 if i < lvl else (clampf((xp - lo) / (hi - lo), 0.0, 1.0) if i == lvl else 0.0)
		row.add_child(_level_box(fill))
	row.tooltip_text = "%s level %d, %d XP to the next" % [name, lvl, maxi(0, roundi(hi - xp))] if lvl < Skills.MAX_LEVEL else "%s maxed" % name
	return row

func _level_box(fill: float) -> Control:
	var back := PanelContainer.new()
	var style := UiTheme.box(UiTheme.BG_HEADER)
	style.set_content_margin_all(0)
	back.add_theme_stylebox_override("panel", style)
	back.custom_minimum_size = BOX
	var bar := ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(BOX.x * fill, BOX.y)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.add_child(bar)
	return back
