## NP1: the morning paper. Opens by itself when a new front page is out
## (NewsSystem, each morning) and on P: the headline, the night's stories,
## city news, and "word on the street" (today's hustles). Read-only.
class_name PaperWindow
extends UiWindow

const ACTION := &"paper"
const WIDTH := 520.0
const INK := Color(0.12, 0.11, 0.1)
const PAGE := Color(0.93, 0.9, 0.82)

var _world: World
var _seen := 0
var _page := VBoxContainer.new()

func setup(world: World, at: Vector2) -> void:
	setup_window("paper", "Morning paper", at, Vector2(WIDTH, 0))
	_world = world
	var sheet := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = PAGE
	box.set_content_margin_all(14)
	sheet.add_theme_stylebox_override("panel", box)
	_page.add_theme_constant_override("separation", 6)
	sheet.add_child(_page)
	body.add_child(sheet)
	body.add_child(UiTheme.label("Esc: close   (the phone's Paper app opens it again)", UiTheme.FONT_SMALL, UiTheme.DIM))
	# PH1: P is the phone now; the paper opens from its Paper app (and by itself each morning)
	visible = false
	var state := _state()
	_seen = state.paper_serial if state != null else 0   # a loaded game does not pop yesterday's paper

func _state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null

func _process(_delta: float) -> void:
	var state := _state()
	if state == null:
		return
	if state.paper_serial != _seen:
		_seen = state.paper_serial
		show_paper(state.paper)
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		close_window()

func show_paper(p: Dictionary) -> void:
	for c in _page.get_children():
		c.queue_free()
	_line(String(p.get("name", NewsSystem.PAPER_NAME)).to_upper(), 24, "marker", HORIZONTAL_ALIGNMENT_CENTER)
	_line("Day %d   ·   25 cents" % int(p.get("day", 1)), 12, "paper", HORIZONTAL_ALIGNMENT_CENTER)
	_page.add_child(_rule())
	_line(String(p.get("headline", "")), 22, "bungee")
	_line(String(p.get("lead", "")), 14, "paper")
	for s in p.get("stories", []):
		_page.add_child(_rule())
		_line(String(s[0]), 15, "bungee")
		_line(String(s[1]), 13, "paper")
	if not (p.get("city", []) as Array).is_empty():
		_page.add_child(_rule())
		_line("AROUND THE CITY", 13, "bungee")
		for c in p["city"]:
			_line("·  " + String(c), 13, "paper")
	if not (p.get("street", []) as Array).is_empty():
		_page.add_child(_rule())
		_line("WORD ON THE STREET", 13, "bungee")
		for c in p["street"]:
			_line("·  " + String(c), 13, "paper")
	visible = true
	reset_size()

func _line(text: String, size: int, font: String, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40.0
	l.horizontal_alignment = align
	l.add_theme_font_override("font", UiTheme.font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	_page.add_child(l)

func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(INK, 0.6)
	r.custom_minimum_size = Vector2(WIDTH - 40.0, 2)
	return r
