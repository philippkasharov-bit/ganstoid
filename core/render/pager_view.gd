## UI1: the pager, top right beside the clock: a 90s beeper's green screen
## with what to do next (NextStep) and today's hustles (HustleSystem), so the
## middle of the screen stays clear for the street. It beeps (blinks) when a
## new hustle day comes in or one is done. Read-only.
class_name PagerView
extends PanelContainer

const WIDTH := 330.0
const REFRESH_S := 0.5
const SCREEN := Color(0.62, 0.74, 0.47)     # backlit LCD
const INK := Color(0.08, 0.12, 0.06)
const CASE := Color(0.09, 0.09, 0.1)
const BLINK_S := 2.4

var clock: Control               # it sits to the left of this
var eye: Control                 # UI2: and keeps clear of the "who sees you" eye in the middle
var _world: World
var _text := Label.new()
var _rows := VBoxContainer.new()
var _rows_key := ""   # UI6: one row per hustle, with a progress bar
var _refresh := 0.0
var _blink := 0.0
var _key := ""

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var case := StyleBoxFlat.new()
	case.bg_color = CASE
	case.set_corner_radius_all(7)
	case.set_content_margin_all(5)
	case.border_color = Color(0.2, 0.2, 0.22)
	case.set_border_width_all(1)
	add_theme_stylebox_override("panel", case)
	var screen := PanelContainer.new()
	var lcd := StyleBoxFlat.new()
	lcd.bg_color = SCREEN
	lcd.set_corner_radius_all(3)
	lcd.content_margin_left = 8
	lcd.content_margin_right = 8
	lcd.content_margin_top = 3
	lcd.content_margin_bottom = 4
	screen.add_theme_stylebox_override("panel", lcd)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("font", UiTheme.font("lcd"))
	_text.add_theme_font_size_override("font_size", 18)
	_text.add_theme_color_override("font_color", INK)
	_text.add_theme_constant_override("line_spacing", -3)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.add_child(_text)
	_rows.add_theme_constant_override("separation", 0)
	col.add_child(_rows)
	screen.add_child(col)
	add_child(screen)
	visible = false

func _process(delta: float) -> void:
	if _world == null:
		return
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var want: bool = p != null and GameRules.of(_world) != null and SimNav.active != null and SimNav.active.usable() and not p.get_component(ComponentNames.NPC).is_down and HudLayout.shown("pager")
	UiMotion.fade(self, want, delta)   # UI6: J hides it; it fades instead of popping
	if not want and not visible:
		return
	_blink = maxf(0.0, _blink - delta)
	modulate.a *= 1.0 if _blink <= 0.0 or fmod(_blink, 0.4) > 0.2 else 0.55
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var next := NextStep.line(_world)
		_text.text = ("> " + next) if next != "" else ""
		_text.visible = next != ""
		var rows_key := str(state.hustles) + str(_world.tick / SimClock.hours(0.25))
		if rows_key != _rows_key:
			_rows_key = rows_key
			_hustle_rows(state)
		var key := str(state.hustle_day) + str(state.hustles.map(func(h: Dictionary) -> bool: return h["done"]))
		if _key != "" and key != _key:
			_blink = BLINK_S   # beep: new hustles, or one done
		_key = key
	var right := clock.position.x - UiTheme.SPACE if clock != null and clock.visible else get_viewport_rect().size.x - UiTheme.MARGIN
	var room := right - (eye.position.x + eye.size.x + UiTheme.SPACE if eye != null and eye.visible else get_viewport_rect().size.x * 0.5) - 16.0
	_text.custom_minimum_size.x = clampf(room, 180.0, WIDTH)   # UI2: narrower (more lines) on a small or scaled-up screen
	reset_size()
	position = HudLayout.place(self, "pager", Vector2(roundf(right - size.x), UiTheme.MARGIN)) + UiMotion.shift(self)

## UI6: a row per hustle: its line, then a bar for how far along it is and
## one (thinner) for how much of the day is left before its deadline.
func _hustle_rows(state: PlayerStateData) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)   # gone now, so the pager shrinks this frame
		c.queue_free()
	for h in state.hustles:
		var line := Label.new()
		line.text = ("[x] " if h["done"] else "[ ] ") + short(_world, h)
		line.add_theme_font_override("font", UiTheme.font("lcd"))
		line.add_theme_font_size_override("font_size", 17)
		line.add_theme_color_override("font_color", INK if not h["done"] else Color(INK, 0.5))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = _text.custom_minimum_size.x
		_rows.add_child(line)
		var f := 1.0 if h["done"] else clampf(float(h["got"]) / float(maxi(1, int(h["need"]))), 0.0, 1.0)
		_rows.add_child(_bar(f, 5.0, INK))
		if not h["done"]:
			var left := clampf(float(int(h["deadline"]) - _world.tick) / float(SimClock.hours(15.0)), 0.0, 1.0)
			_rows.add_child(_bar(left, 2.0, Color(0.55, 0.12, 0.08)))

func _bar(f: float, h: float, ink: Color) -> Control:
	var back := ColorRect.new()
	back.color = Color(ink, 0.18)
	back.custom_minimum_size = Vector2(_text.custom_minimum_size.x, h)
	var fill := ColorRect.new()
	fill.color = ink
	fill.size = Vector2(_text.custom_minimum_size.x * f, h)
	back.add_child(fill)
	return back

## The screen as text: "> next step", then a line per hustle (checks, notes).
static func text_for(world: World, state: PlayerStateData) -> String:
	var lines: PackedStringArray = []
	var next := NextStep.line(world)
	if next != "":
		lines.append("> " + next)
	for h in state.hustles:
		lines.append(("[x] " if h["done"] else "[ ] ") + short(world, h))
	return "\n".join(lines)

## "Move 3 bags of product 1/3 $120 ->22h"
static func short(_world: World, h: Dictionary) -> String:
	var spec: Array = HustleSystem.KINDS[h["kind"]]
	var progress := "$%d/%d" % [int(h["got"]), int(h["need"])] if spec[6] else "%d/%d" % [mini(int(h["got"]), int(h["need"])), int(h["need"])]
	var until := int(SimClock.day_fraction(int(h["deadline"])) * 24.0) % 24
	return "%s %s $%d ->%02dh" % [HustleSystem.text_of(h), "DONE" if h["done"] else progress, int(h["pay"]), until]
