## UI6: the HUD the player arranges. Each panel has an id; its position is
## its own default plus an offset the player dragged it by (F10: layout mode),
## and some can be hidden with a key (J pager, O minimap). Kept in
## user://settings.cfg with the UI size (UiSettings), not in the save.
class_name HudLayout
extends RefCounted

const PATH := UiSettings.PATH
## id -> [name, toggle action (or &""), key]
const PANELS := {
	"card": ["Status", &"", KEY_NONE],
	"pager": ["Pager", &"toggle_pager", KEY_J],
	"minimap": ["Minimap", &"toggle_minimap", KEY_O],
	"tips": ["Tips", &"", KEY_NONE],
	"eye": ["Who sees you", &"", KEY_NONE],
	"notify": ["Messages", &"", KEY_NONE],
}
const EDIT_ACTION := &"hud_layout"

static var editing := false
static var _offsets: Dictionary = {}
static var _hidden: Dictionary = {}
static var _loaded := false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if Engine.has_meta("no_save") or cfg.load(PATH) != OK:   # the screen tests use the default layout
		return
	for id in PANELS:
		var o: Variant = cfg.get_value("layout", id, Vector2.ZERO)
		if typeof(o) == TYPE_VECTOR2 and absf(o.x) < 10000.0 and absf(o.y) < 10000.0:
			_offsets[id] = o
		if cfg.get_value("hidden", id, false) == true:
			_hidden[id] = true

static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for id in PANELS:
		cfg.set_value("layout", id, _offsets.get(id, Vector2.ZERO))
		cfg.set_value("hidden", id, _hidden.get(id, false))
	cfg.save(PATH)

## Where panel `id` goes: its default spot plus the player's offset, kept on screen.
static func place(c: Control, id: String, default_pos: Vector2) -> Vector2:
	_load()
	var view := c.get_viewport_rect().size
	var p: Vector2 = default_pos + _offsets.get(id, Vector2.ZERO)
	return Vector2(clampf(p.x, 0.0, maxf(0.0, view.x - c.size.x)), clampf(p.y, 0.0, maxf(0.0, view.y - c.size.y))).round()

static func move(id: String, by: Vector2) -> void:
	_load()
	_offsets[id] = _offsets.get(id, Vector2.ZERO) + by

static func shown(id: String) -> bool:
	_load()
	return not _hidden.get(id, false)

static func toggle(id: String) -> void:
	_load()
	_hidden[id] = not _hidden.get(id, false)
	_save()

static func reset() -> void:
	_offsets.clear()
	_hidden.clear()
	_save()
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	if cfg.has_section("windows"):
		cfg.erase_section("windows")
	cfg.save(PATH)

static func done_editing() -> void:
	editing = false
	_save()

## UI6: a window's saved spot (dragged by its title bar), else `fallback`.
static func window_pos(id: String, fallback: Vector2) -> Vector2:
	var cfg := ConfigFile.new()
	if Engine.has_meta("no_save") or cfg.load(PATH) != OK:
		return fallback
	var v: Variant = cfg.get_value("windows", id, fallback)
	return v if typeof(v) == TYPE_VECTOR2 and v.x >= 0.0 and v.y >= 0.0 and v.x < 8000.0 and v.y < 8000.0 else fallback

static func save_window(id: String, at: Vector2) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("windows", id, at)
	cfg.save(PATH)

static func bind_keys() -> void:
	for id in PANELS:
		if PANELS[id][1] != &"":
			CharacterWindow._bind(PANELS[id][1], PANELS[id][2])
	CharacterWindow._bind(EDIT_ACTION, KEY_F10)
