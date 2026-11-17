## JL1: the prison panel, open the whole time you're inside: days left, what
## today is for (PrisonSystem's choices: click one) and the odds of a run.
## Read-only: a click only asks (ui_prison).
class_name PrisonWindow
extends PanelContainer

var _world: World
var _col := VBoxContainer.new()
var _key := ""

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiPanel.card_style())
	_col.add_theme_constant_override("separation", 6)
	add_child(_col)
	visible = false

func _process(_delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
	visible = state != null and state.prison_until_tick > 0 and state.verdict.is_empty()   # CT1: the court first
	if not visible:
		return
	var left := maxf(0.0, float(state.prison_until_tick - _world.tick) / SimClock.day_ticks)
	var key := "%.1f|%s" % [left, state.prison_choice]
	if key != _key:
		_key = key
		for c in _col.get_children():
			_col.remove_child(c)
			c.queue_free()
		var title := UiTheme.label("COUNTY JAIL", 22, UiTheme.ACCENT)
		title.add_theme_font_override("font", UiTheme.font("marker"))
		_col.add_child(title)
		_col.add_child(UiTheme.label("%.1f days left" % left, UiTheme.FONT_TITLE, UiTheme.TEXT))
		_col.add_child(UiTheme.label("How do you spend the days?", UiTheme.FONT_SMALL, UiTheme.DIM))
		for ch in PrisonSystem.CHOICES:
			var b := Button.new()
			var text := PrisonSystem.choice_text(ch)
			if ch == "escape":
				text += "  · odds %d%%" % roundi(PrisonSystem.escape_odds(_world, state) * 100.0)
			b.text = ("> " if state.prison_choice == ch else "   ") + text
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			var pick: String = ch
			b.pressed.connect(func() -> void: state.ui_prison = pick)
			_col.add_child(b)
		reset_size()
	var view := get_viewport_rect().size
	position = ((view - size) * 0.5).round()
