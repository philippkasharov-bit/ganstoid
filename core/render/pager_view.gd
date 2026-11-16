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
	screen.add_child(_text)
	add_child(screen)
	visible = false

func _process(delta: float) -> void:
	if _world == null:
		return
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	visible = p != null and GameRules.of(_world) != null and SimNav.active != null and SimNav.active.usable() and not p.get_component(ComponentNames.NPC).is_down
	if not visible:
		return
	_blink = maxf(0.0, _blink - delta)
	modulate.a = 1.0 if _blink <= 0.0 or fmod(_blink, 0.4) > 0.2 else 0.55
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		_text.text = text_for(_world, state)
		var key := str(state.hustle_day) + str(state.hustles.map(func(h: Dictionary) -> bool: return h["done"]))
		if _key != "" and key != _key:
			_blink = BLINK_S   # beep: new hustles, or one done
		_key = key
	var right := clock.position.x - UiTheme.SPACE if clock != null and clock.visible else get_viewport_rect().size.x - UiTheme.MARGIN
	var room := right - (eye.position.x + eye.size.x + UiTheme.SPACE if eye != null and eye.visible else get_viewport_rect().size.x * 0.5) - 16.0
	_text.custom_minimum_size.x = clampf(room, 180.0, WIDTH)   # UI2: narrower (more lines) on a small or scaled-up screen
	reset_size()
	position = Vector2(roundf(right - size.x), UiTheme.MARGIN)

## The screen: "> next step", then a line per hustle.
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
