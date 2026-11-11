## UI1: the game's one panel style (dark card, gold accent edge, numbered
## rows) so every menu looks like part of the same game. Subclasses fill
## `refresh()` with show(title, rows, footer) or hide.
class_name UiPanel
extends PanelContainer

const BG := Color(0.06, 0.06, 0.08, 0.93)
const ACCENT := Color(0.95, 0.72, 0.2)
const TEXT := Color(0.92, 0.92, 0.9)
const DIM := Color(0.6, 0.6, 0.62)
const KEY_BG := Color(0.95, 0.72, 0.2, 0.18)

var _world: World
var _title := Label.new()
var _rows := VBoxContainer.new()
var _footer := Label.new()

func setup(world: World, at: Vector2) -> void:
	_world = world
	position = at
	custom_minimum_size = Vector2(340, 0)
	add_theme_stylebox_override("panel", card_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", ACCENT)
	box.add_child(_title)
	box.add_child(HSeparator.new())
	_rows.add_theme_constant_override("separation", 3)
	box.add_child(_rows)
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", DIM)
	box.add_child(_footer)
	visible = false

## The shared card look (also used by the status card and toasts).
static func card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = ACCENT
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	return style

func _process(_delta: float) -> void:
	if _world != null:
		refresh()

func refresh() -> void:
	pass

## rows: Array of [key text ("1", "" for none), label, right-hand text]
func show_panel(title: String, rows: Array, footer: String) -> void:
	visible = true
	_title.text = title.to_upper()
	_footer.text = footer
	var key := str(rows.hash()) + title
	if get_meta("key", "") == key:
		return   # unchanged: do not rebuild the rows every frame
	set_meta("key", key)
	for c in _rows.get_children():
		c.queue_free()
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
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
		line.add_child(k)
		line.add_child(t)
		line.add_child(v)
		_rows.add_child(line)

func player_state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
