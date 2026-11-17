## UI2: the player's interface settings, kept in user://settings.cfg (not in
## the save: they belong to the machine, not the life). For now the interface
## size: the whole HUD and windows scale (Window.content_scale_factor; the 3D
## city is not touched). The first run picks one for the screen's height.
class_name UiSettings
extends RefCounted

const PATH := "user://settings.cfg"
const SIZES := [0.85, 1.0, 1.15, 1.3, 1.5]

## The saved size, or one picked for this screen.
static func ui_scale() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var v: Variant = cfg.get_value("ui", "scale", 0.0)
		if typeof(v) == TYPE_FLOAT and SIZES.has(v):
			return v
	return auto_scale(DisplayServer.screen_get_size().y)

## 720p and below 100%, 1080p 115%, 1440p 130%, 4K 150%.
static func auto_scale(screen_h: int) -> float:
	if screen_h >= 2000:
		return 1.5
	if screen_h >= 1400:
		return 1.3
	if screen_h >= 1000:
		return 1.15
	return 1.0

static func apply(root: Window, scale: float) -> void:
	root.content_scale_factor = scale

## AD1: admin tools on (pause menu)? Off unless switched on.
static func admin() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(PATH) == OK and cfg.get_value("admin", "on", false) == true

static func set_admin(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("admin", "on", on)
	cfg.save(PATH)

## The next size up (wrapping round), applied and saved.
static func cycle(root: Window) -> float:
	var now := ui_scale()
	var next: float = SIZES[(SIZES.find(now) + 1) % SIZES.size()] if SIZES.has(now) else 1.0
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("ui", "scale", next)
	cfg.save(PATH)
	apply(root, next)
	return next
