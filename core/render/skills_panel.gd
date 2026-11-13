## SK2: the Skills tab of the Character Info window, Project Zomboid's: skills
## under group headings (Combat, Crime, Vehicles), each with ten level boxes;
## full boxes are levels earned, the next box fills as XP comes in. Hover a
## skill for its card: level, XP to the next, what the levels give you and
## how to train it. Read-only.
class_name SkillsPanel
extends VBoxContainer

const BOX := Vector2(12, 10)
const NAME_W := 76.0

var _tip := UiTooltip.new()
var _key := ""
var _levels := {}   # A7: skill -> level last shown, to shine a box just earned
var _shine := {}    # skill -> when its new box started to shine
var _clock := 0.0
const SHINE_S := 1.2

func _process(delta: float) -> void:
	_clock += delta
	if not _shine.is_empty():
		for row in get_children():
			if row.has_meta("skill") and _shine.has(row.get_meta("skill")):
				row.queue_redraw()
				for c in row.get_child(0).get_children():
					c.queue_redraw()

func _init() -> void:
	add_theme_constant_override("separation", 2)
	add_child(_tip)
	_tip.top_level = true

func refresh(state: PlayerStateData) -> void:
	var key := str(state.skills)
	if key == _key:
		return
	_key = key
	for c in get_children():
		if c != _tip:
			remove_child(c)
			c.queue_free()
	for g in Skills.GROUPS:
		add_child(_heading(g[0]))
		for s in g[1]:
			var lvl: int = Skills.progress(float(state.skills.get(s, 0.0)))[0]
			if _levels.has(s) and lvl > int(_levels[s]):
				_shine[s] = _clock
			_levels[s] = lvl
			add_child(_row(s, float(state.skills.get(s, 0.0))))

func hide_tip() -> void:
	_tip.hide_tip()

func _heading(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	if get_child_count() > 1:
		var gap := Control.new()
		gap.custom_minimum_size.y = UiTheme.GAP
		box.add_child(gap)
	box.add_child(UiTheme.label(text.to_upper(), 10, UiTheme.DIM))
	box.add_child(UiTheme.divider())
	return box

## Name, then ten boxes; the whole row lights on hover and shows the card.
func _row(skill: StringName, xp: float) -> Control:
	var p := Skills.progress(xp)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var idle := StyleBoxEmpty.new()
	var lit := UiTheme.box(UiTheme.BG_ROW_HOVER, Color.TRANSPARENT, 0)
	for look in [idle, lit]:
		look.set_content_margin_all(0)   # same insets lit or not, so nothing shifts on hover
		look.content_margin_top = 2
		look.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", idle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := UiTheme.label(String(skill).capitalize(), UiTheme.FONT_SMALL, UiTheme.TEXT)
	title.custom_minimum_size.x = NAME_W
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	for i in Skills.MAX_LEVEL:
		var fill: float = 1.0 if i < p[0] else (p[1] / p[2] if i == p[0] and p[2] > 0.0 else 0.0)
		row.add_child(_box(fill, skill if i == p[0] - 1 else &""))
	panel.add_child(row)
	panel.set_meta("skill", skill)
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", lit)
		_tip.show_at(panel.global_position + Vector2(panel.size.x, 0), String(skill).capitalize(), card(skill, xp), "Train: " + Skills.XP_FROM[skill]))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", idle)
		_tip.hide_tip())
	return panel

## [text, colour] lines of a skill's hover card.
static func card(skill: StringName, xp: float) -> Array:
	var p := Skills.progress(xp)
	var lines: Array = [["Level %d / %d" % [p[0], Skills.MAX_LEVEL], UiTheme.ACCENT]]
	lines.append(["Maxed out", UiTheme.GOOD] if p[2] <= 0.0 else ["XP %d / %d to the next" % [roundi(p[1]), roundi(p[2])], UiTheme.TEXT])
	var edge: int = roundi(Skills.EDGE_PER_LEVEL * 100 * p[0])
	lines.append(["+%d%% %s" % [edge, Skills.PER_LEVEL[skill]] if edge > 0 else "No edge yet: %d%% %s per level" % [roundi(Skills.EDGE_PER_LEVEL * 100), Skills.PER_LEVEL[skill]], UiTheme.GOOD if edge > 0 else UiTheme.DIM])
	return lines

func _box(fill: float, newest: StringName) -> Control:
	var c := Control.new()
	c.custom_minimum_size = BOX
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		c.draw_rect(Rect2(Vector2.ZERO, BOX), UiTheme.BG_HEADER)
		if fill > 0.0:
			c.draw_rect(Rect2(Vector2.ZERO, Vector2(BOX.x * fill, BOX.y)), UiTheme.ACCENT if fill >= 1.0 else UiTheme.ACCENT.darkened(0.25))
		c.draw_rect(Rect2(Vector2.ZERO, BOX), Color(1, 1, 1, 0.12), false, 1.0)
		if newest != &"" and _shine.has(newest):   # A7: a white glint sweeps the box just earned
			var t: float = (_clock - float(_shine[newest])) / SHINE_S
			if t < 1.0:
				var x := BOX.x * (t * 2.0 - 0.5)
				c.draw_rect(Rect2(Vector2(clampf(x, 0.0, BOX.x), 0), Vector2(clampf(4.0, 0.0, BOX.x - clampf(x, 0.0, BOX.x)), BOX.y)), Color(1, 1, 1, 0.8 * (1.0 - t)))
				c.draw_rect(Rect2(Vector2.ZERO, BOX), Color(1, 1, 1, 0.5 * (1.0 - t)), false, 1.5)
			else:
				_shine.erase(newest))
	return c
