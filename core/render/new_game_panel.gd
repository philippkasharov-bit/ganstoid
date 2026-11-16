## O1/UI5: a new life. The title screen: the street art behind, the name big,
## then two picks as three tilted Polaroid cards each (how hard, then how you
## want to play). Click a card or press 1-3. The world waits until both are picked.
class_name NewGamePanel
extends Control

const CARD := Vector2(230, 190)
const GAP := 26.0
const PAPER := Color(0.94, 0.92, 0.86)
const INK := Color(0.1, 0.09, 0.08)
const TILTS := [-0.045, 0.02, -0.025]

var _driver: Node
var _difficulty := -1
var _cards := HBoxContainer.new()
var _question := Label.new()
var _shown := -2

func open(driver: Node) -> void:
	_driver = driver
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := TextureRect.new()
	back.texture = UiTheme.image(UiTheme.STREET + "title.jpg")
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.modulate = Color(0.55, 0.55, 0.6)
	add_child(back)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var logo := _label("TAGGED", "marker", 92, UiTheme.ACCENT)
	logo.add_theme_constant_override("outline_size", 10)
	logo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	col.add_child(logo)
	col.add_child(_label("Downtown Los Angeles. Start with $40. Get known.", "paper", 16, Color(0.9, 0.88, 0.82)))
	var space := Control.new()
	space.custom_minimum_size.y = 18
	col.add_child(space)
	_question.add_theme_font_override("font", UiTheme.font("bungee"))
	_question.add_theme_font_size_override("font_size", 22)
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_question)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", int(GAP))
	col.add_child(_cards)
	col.add_child(_label("Click a card or press 1, 2 or 3", "paper", 13, Color(0.8, 0.8, 0.78)))

func _label(text: String, font: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _process(_delta: float) -> void:
	if _driver == null or not _driver.choosing:
		visible = false
		return
	visible = true
	if _shown != _difficulty:
		_shown = _difficulty
		_build()

## The three cards of the current question.
func _build() -> void:
	for c in _cards.get_children():
		c.queue_free()
	var picking_style := _difficulty >= 0
	_question.text = "HOW DO YOU WANT TO PLAY?" if picking_style else "HOW HARD?"
	var names: Array = GameRules.STYLES if picking_style else GameRules.DIFFICULTIES
	var texts: Array = GameRules.STYLE_TEXT if picking_style else GameRules.DIFFICULTY_TEXT
	for i in 3:
		_cards.add_child(_card(i, String(names[i]), String(texts[i]), picking_style and i == 1 or not picking_style and i == 1))

func _card(i: int, title: String, text: String, suggested: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = CARD
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.set_content_margin_all(14)
	box.content_margin_bottom = 26   # a Polaroid's thicker bottom edge
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 8
	box.shadow_offset = Vector2(3, 5)
	card.add_theme_stylebox_override("panel", box)
	card.size = CARD
	card.pivot_offset = CARD * 0.5
	card.rotation = TILTS[i]
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var head := HBoxContainer.new()
	var key := _label(" %d " % (i + 1), "bungee", 16, INK)
	var kb := StyleBoxFlat.new()
	kb.bg_color = UiTheme.ACCENT
	kb.set_corner_radius_all(3)
	key.add_theme_stylebox_override("normal", kb)
	head.add_child(key)
	var name := _label(title.to_upper(), "bungee", 20, INK)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(name)
	col.add_child(head)
	var body := _label(text, "paper", 13, INK)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = CARD.x - 28
	col.add_child(body)
	if suggested:
		var tag := _label("most people start here", "marker", 13, Color(0.7, 0.2, 0.15))
		col.add_child(tag)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_choose(i))
	card.mouse_entered.connect(func() -> void: card.scale = Vector2.ONE * 1.05)
	card.mouse_exited.connect(func() -> void: card.scale = Vector2.ONE)
	holder.add_child(card)
	return holder

func _unhandled_input(event: InputEvent) -> void:
	if _driver == null or not _driver.choosing or not (event is InputEventKey) or not event.pressed:
		return
	var k: int = event.physical_keycode - KEY_1
	if k < 0 or k > 2:
		return
	_choose(k)
	get_viewport().set_input_as_handled()

func _choose(k: int) -> void:
	if _difficulty < 0:
		_difficulty = k
	else:
		_driver.choose(_difficulty, k)
