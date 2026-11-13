## UI4/UI16/UI18: the one visual language for every panel. UI18: every panel
## is a page of a graffiti blackbook: black sketchbook paper, the title written
## on a white paint-marker swipe, marker-line dividers, masking tape on the
## corners, a sticker or two; tooltips are torn notebook scraps. Before that a cassette label for the
## title bar (marker-pen title), a gold rope chain for dividers, Bungee for
## numbers. Panels read colours, fonts and boxes from here, so restyling the
## game stays a one-file change. Art lives in art/ui/street/, swappable.
class_name UiTheme
extends RefCounted

const BG := Color(0.07, 0.075, 0.08, 0.94)
const BG_HEADER := Color(0.13, 0.135, 0.14, 0.98)
const BG_ROW_HOVER := Color(1, 1, 1, 0.07)
const BG_ROW_SELECT := Color(0.95, 0.72, 0.2, 0.16)
const FRAME := Color(0.42, 0.42, 0.40, 0.9)
const ACCENT := Color(0.95, 0.72, 0.2)
const TEXT := Color(0.88, 0.87, 0.83)
const DIM := Color(0.58, 0.58, 0.56)
const GOOD := Color(0.45, 0.78, 0.42)
const BAD := Color(0.86, 0.32, 0.28)

const FONT_SMALL := 11
const FONT_BODY := 12
const FONT_TITLE := 13
const HEADER_H := 24
## UI25: one spacing scale (4 / 8 / 12) and one margin for everything on screen.
const GAP := 4
const SPACE := 8
const MARGIN := 12
const RADIUS := 4
const LINE := Color(1, 1, 1, 0.08)
const INK := Color(0.12, 0.11, 0.13)          # marker ink on the cassette label
const STREET := "res://art/ui/street/"
const PAD := 8
const ROW_H := 20

static func box(bg: Color, border: Color = FRAME, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_content_margin_all(PAD)
	return style

const PANEL := Color("141416")
const PIPING := Color(0.91, 0.89, 0.82, 0.9)
const DROP := Color("5b2a8c")            # hard, offset, no blur: printed-flyer shadow

static func window_box(margin: int = 2) -> StyleBox:
	var style := box(Color(0.06, 0.065, 0.075, 0.94), Color(1, 1, 1, 0.1), 1)   # UI25: flat, soft shadow, small radius
	style.set_corner_radius_all(RADIUS)
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	return style

## The cassette label: cream with red and blue stripes, title in marker.
static func header_box() -> StyleBox:
	var style := box(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0)   # UI25: a quiet title strip, hairline under it
	style.border_width_bottom = 1
	style.border_color = LINE
	style.corner_radius_top_left = RADIUS
	style.corner_radius_top_right = RADIUS
	style.set_content_margin_all(0)
	style.content_margin_left = PAD + 2
	style.content_margin_right = GAP
	return style

## UI25: an icon button face: idle, hover (lighter), on (gold edge).
static func button_box(state: String) -> StyleBoxFlat:
	var style := box(Color(0.06, 0.065, 0.075, 0.94), Color(1, 1, 1, 0.1), 1)
	style.set_corner_radius_all(RADIUS)
	style.set_content_margin_all(GAP)
	if state == "hover":
		style.bg_color = Color(0.12, 0.125, 0.14, 0.96)
		style.border_color = Color(1, 1, 1, 0.22)
	elif state == "on":
		style.border_color = ACCENT
		style.set_border_width_all(2)
	return style

static var _images := {}

## A picture by path, or null when the file is missing. Falls back to reading
## the file itself when Godot has not imported it (a fresh copy run without
## the editor), so icons and title art never turn into letters.
static func image(path: String) -> Texture2D:
	if _images.has(path):
		return _images[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		tex = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	_images[path] = tex
	return tex

## A tiled art box from art/ui/street/<name>.png, or null when it is missing.
static func texture_box(name: String, tint: Color, margin: int, tile: bool = false) -> StyleBoxTexture:
	var tex := image(STREET + name + ".png")
	if tex == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.modulate_color = tint
	if tile:
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.set_content_margin_all(margin)
	return style

## Gold rope chain in place of a plain line.
static func divider() -> Control:
	var line := ColorRect.new()   # UI20: a hairline, nothing more
	line.color = Color(1, 1, 1, 0.1)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

static var _fonts := {}

## marker (titles), bungee (numbers, keys), lcd (pager), paper (newspaper).
static func font(kind: String) -> Font:
	if not _fonts.has(kind):
		var file: String = {"marker": "PermanentMarker", "bungee": "Bungee", "lcd": "VT323", "paper": "SpecialElite"}[kind]
		var path := "res://fonts/%s-Regular.ttf" % file
		_fonts[kind] = load(path) if ResourceLoader.exists(path) else _font_file(path)
	return _fonts[kind]

## A font straight from its file when it is not imported; the default if missing.
static func _font_file(path: String) -> Font:
	if not FileAccess.file_exists(path):
		return ThemeDB.fallback_font
	var f := FontFile.new()
	f.load_dynamic_font(path)
	return f

## A piece of art from art/ui/street/<name>.png as a fixed-size decoration
## (tape, sticker, doodle), or null when the file is missing.
static func decal(name: String, height: float, angle_deg: float) -> TextureRect:
	var tex := image(STREET + name + ".png")
	if tex == null:
		return null
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex_size: Vector2 = t.texture.get_size()
	t.size = Vector2(height * tex_size.x / tex_size.y, height)
	t.pivot_offset = t.size * 0.5
	t.rotation_degrees = angle_deg
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func title_label(text: String) -> Label:
	var l := label(text, FONT_TITLE, TEXT)   # UI25: white titles; gold is kept for what is selected or yours
	return l

static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## UI26: a row of input prompts, each a keycap then what it does:
## key_hints([["LMB drag", "move"], ["RMB", "eat · equip · drop"]]). Wraps to
## more lines when narrow. Every window footer uses this one look.
static func key_hints(pairs: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 3)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in pairs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(keycap(p[0]))
		row.add_child(label(p[1], FONT_SMALL, DIM))
		flow.add_child(row)
	return flow

## One key in a small light-edged box ("E", "RMB", "Esc").
static func keycap(key: String) -> Control:
	var cap := PanelContainer.new()
	var face := box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.28), 1)
	face.set_corner_radius_all(3)
	face.border_width_bottom = 2
	face.content_margin_left = 4
	face.content_margin_right = 4
	face.content_margin_top = 0
	face.content_margin_bottom = 0
	cap.add_theme_stylebox_override("panel", face)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(label(key, 10, TEXT))
	return cap
