## UI6/UI19/CI1: the Character Info window, Project Zomboid's: one window,
## tabs Info (rank, fame, traits, crew, businesses), Skills (ten level boxes
## per skill, the next box filling as XP comes in) and Health (the body panel).
## K opens it on Info, H (or the side bar's heart) on Health; the same key
## again closes it. Only the Health tab writes (its treatments).
class_name CharacterWindow
extends UiWindow

const ACTION := &"skills_window"
const HEALTH_ACTION := &"health_window"
const TAB_INFO := 0
const TAB_HEALTH := 2
const BOX := Vector2(11, 9)

var _world: World
var _rows := VBoxContainer.new()
var _info := VBoxContainer.new()
var _tabs := UiTabs.new()
var _health := HealthPanel.new()
var _key := ""

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("character", "Character", at, Vector2(250, 0))
	_rows.add_theme_constant_override("separation", 3)
	_info.add_theme_constant_override("separation", 2)
	body.add_child(_tabs)
	_tabs.add_tab("Info", _info)
	_tabs.add_tab("Skills", _rows)
	_health.setup(world)
	_tabs.add_tab("Health", _health)
	_tabs.changed.connect(func(_i: int) -> void:   # fit each tab (Health is the wide one) and stay on screen
		reset_size()
		_keep_on_screen.call_deferred())
	_tabs.pick(TAB_INFO)
	_bind(ACTION, KEY_K)
	_bind(HEALTH_ACTION, KEY_H)
	visible = false

static func _bind(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

## K / H: open on that tab, or close if it is already showing.
func open_tab(tab: int) -> void:
	var on_health := _tabs.current == TAB_HEALTH
	if visible and (tab == TAB_HEALTH) == on_health:
		close_window()
		return
	visible = true
	_tabs.pick(tab)

func showing_health() -> bool:
	return visible and _tabs.current == TAB_HEALTH

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION):
		open_tab(TAB_INFO)
	elif Input.is_action_just_pressed(HEALTH_ACTION):
		open_tab(TAB_HEALTH)
	elif visible and Input.is_action_just_pressed("ui_cancel") and not _health.close_menu():
		close_window()
	if not visible or _world == null:
		_health.close_menu()
		return
	if _tabs.current == TAB_HEALTH:
		_health.refresh()
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var key := "%s|%d|%d|%d" % [state.skills, state.rank, roundi(state.fame), state.crew_ids.size()]
	if key != _key:
		_key = key
		_rebuild(state)
		_rebuild_info(state)

func _rebuild_info(state: PlayerStateData) -> void:
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var rank := UiTheme.label(RankSystem.name_of(state.rank), UiTheme.FONT_TITLE, UiTheme.ACCENT)
	_info.add_child(rank)
	for line in [["Next rank", "%d pts" % RankSystem.to_next(_world, npc, state)], ["Fame", str(roundi(state.fame))],
			["Crew", "%d/%d" % [state.crew_ids.size(), CrewSystem.MAX_CREW]],
			["Businesses", str(BusinessSystem.count_owned(_world))], ["Labs", str(ProductionSystem.count_grow_houses(_world))]]:
		_info.add_child(_stat_row(line[0], line[1]))
	_info.add_child(UiTheme.divider())
	var traits := UiTheme.label("Traits: " + Traits.summary(state), UiTheme.FONT_SMALL, UiTheme.DIM)
	traits.autowrap_mode = TextServer.AUTOWRAP_WORD
	traits.custom_minimum_size.x = 230
	_info.add_child(traits)

## "Fame ........ 12": name left, number right in Bungee.
static func _stat_row(name: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var n := UiTheme.label(name, UiTheme.FONT_SMALL, UiTheme.DIM)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiTheme.label(value, UiTheme.FONT_SMALL, UiTheme.TEXT)
	row.add_child(n)
	row.add_child(v)
	return row

func _rebuild(state: PlayerStateData) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for s in Skills.NAMES:
		_rows.add_child(_skill_row(String(s).capitalize(), state.skills.get(s, 0.0)))

## Level n starts at 25 n^2 XP; the box after the last full one shows progress.
func _skill_row(name: String, xp: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var title := UiTheme.label(name)
	title.custom_minimum_size.x = 70
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
