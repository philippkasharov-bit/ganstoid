## CT1: the day in court, after the court sits: each witness and what they
## said (or why they didn't), then the verdict. Read-only: Close only asks
## (ui_court). Shown over the prison panel until closed.
class_name CourtWindow
extends PanelContainer

const TONES := {-1: UiTheme.BAD, 1: UiTheme.GOOD, 0: UiTheme.DIM}

var _world: World
var _col := VBoxContainer.new()
var _shown: Dictionary = {}

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiPanel.card_style())
	_col.add_theme_constant_override("separation", 6)
	add_child(_col)
	visible = false

func _process(_delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
	visible = state != null and not state.verdict.is_empty()
	if not visible:
		_shown = {}
		return
	if not is_same(state.verdict, _shown):
		_shown = state.verdict
		_build(state)
	var view := get_viewport_rect().size
	position = ((view - size) * 0.5).round()

func _build(state: PlayerStateData) -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var v := state.verdict
	var title := UiTheme.label("SUPERIOR COURT", 22, UiTheme.ACCENT)
	title.add_theme_font_override("font", UiTheme.font("marker"))
	_col.add_child(title)
	_col.add_child(UiTheme.label("The People v. you", UiTheme.FONT_SMALL, UiTheme.DIM))
	_col.add_child(UiTheme.divider())
	var lines: Array = v.get("lines", [])
	if lines.is_empty():
		_col.add_child(UiTheme.label("No witnesses. Only the file.", UiTheme.FONT_SMALL, UiTheme.TEXT))
	for l in lines:
		var row := UiTheme.label("%s  %s" % [l[0], l[1]], UiTheme.FONT_SMALL, TONES.get(int(l[2]), UiTheme.TEXT))
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size.x = 380
		_col.add_child(row)
	if float(v.get("lawyer", 0.0)) > 0.0:
		_col.add_child(UiTheme.label("Your lawyer took %d off the case." % int(v["lawyer"]), UiTheme.FONT_SMALL, UiTheme.GOOD))
	_col.add_child(UiTheme.divider())
	var guilty: bool = v.get("guilty", false)
	var verdict := UiTheme.label("GUILTY: %d DAYS" % int(v.get("days", 0)) if guilty else "NOT GUILTY", UiTheme.FONT_TITLE, UiTheme.BAD if guilty else UiTheme.GOOD)
	_col.add_child(verdict)
	var b := Button.new()
	b.text = "Close"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: state.ui_court = "close")
	_col.add_child(b)
	reset_size()
