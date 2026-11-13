## UI1: the game's one panel style (dark card, gold accent edge, numbered
## rows) so every menu looks like part of the same game. Subclasses fill
## `refresh()` with show(title, rows, footer) or hide.
class_name UiPanel
extends PanelContainer

signal row_picked(index: int)   # UIF1: a numbered row was clicked

const BG := UiTheme.BG
const ACCENT := UiTheme.ACCENT
const TEXT := UiTheme.TEXT
const DIM := UiTheme.DIM
const KEY_BG := Color(0.95, 0.72, 0.2, 0.18)

var _world: World
var _title := Label.new()
var _rows := VBoxContainer.new()
var _footer := MarginContainer.new()   # UI26: keycap prompts
var _footer_key := ""

func setup(world: World, at: Vector2) -> void:
	_world = world
	position = at
	custom_minimum_size = Vector2(240, 0)
	add_theme_stylebox_override("panel", card_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", ACCENT)
	box.add_child(_title)
	box.add_child(UiTheme.divider())
	_rows.add_theme_constant_override("separation", 1)
	box.add_child(_rows)
	_footer.add_theme_constant_override("margin_top", 2)
	box.add_child(_footer)
	row_picked.connect(_on_row)
	visible = false

## A clicked row: by default the open game menu's row (the input system acts on it).
func _on_row(index: int) -> void:
	var state := player_state()
	if state != null:
		state.ui_pick = index

## The shared card look (also used by the status card and toasts).
static func card_style() -> StyleBox:
	return UiTheme.window_box(8)   # UI17: same flat jacket panel as the windows

func _process(_delta: float) -> void:
	if _world != null:
		refresh()

func refresh() -> void:
	pass

## rows: Array of [key text ("1", "" for none), label, right-hand text];
## hints: [[key, what it does], ...] shown as keycaps under the rows.
func show_panel(title: String, rows: Array, hints: Array) -> void:
	visible = true
	_title.text = title.to_upper()
	_set_hints(hints)
	var key := str(rows.hash()) + title
	if get_meta("key", "") == key:
		return   # unchanged: do not rebuild the rows every frame
	set_meta("key", key)
	for c in _rows.get_children():
		c.queue_free()
	var numbered := 0
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var k := Label.new()
		k.text = " %s " % r[0] if r[0] != "" else "   "
		k.add_theme_color_override("font_color", ACCENT)
		var kb := StyleBoxFlat.new()
		kb.bg_color = KEY_BG if r[0] != "" else Color.TRANSPARENT
		kb.set_corner_radius_all(3)
		k.add_theme_stylebox_override("normal", kb)
		var t := Label.new()
		t.text = r[1]
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_color_override("font_color", TEXT if r[0] != "" else DIM)
		var v := Label.new()
		v.text = r[2]
		v.add_theme_color_override("font_color", DIM)
		for part in [k, t, v]:
			part.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)   # UI18: compact rows
		line.add_child(k)
		line.add_child(t)
		line.add_child(v)
		_rows.add_child(_clickable(line, numbered) if r[0] != "" else line)
		if r[0] != "":
			numbered += 1

func _set_hints(hints: Array) -> void:
	var key := str(hints)
	if key == _footer_key:
		return
	_footer_key = key
	for c in _footer.get_children():
		c.queue_free()
	_footer.visible = not hints.is_empty()
	if _footer.visible:
		_footer.add_child(UiTheme.key_hints(hints))

## UIF1: a numbered row is a flat button too, so the mouse works like 1-9.
func _clickable(line: HBoxContainer, index: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = UiTheme.ROW_H
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BG_ROW_HOVER, Color.TRANSPARENT, 0))
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in line.get_children():
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(line)
	b.pressed.connect(func() -> void: row_picked.emit(index))
	return b

func player_state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
