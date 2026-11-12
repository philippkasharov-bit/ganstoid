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
const HEADER_H := 20
const INK := Color(0.12, 0.11, 0.13)          # marker ink on the cassette label
const STREET := "res://art/ui/street/"
const PAD := 5
const ROW_H := 18

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
	var page := texture_box("book/page", Color.WHITE, margin)
	if page != null:
		page.texture_margin_left = 10   # nine-patch keeps the paper edge crisp at any size
		page.texture_margin_right = 10
		page.texture_margin_top = 10
		page.texture_margin_bottom = 10
		return page
	var style := box(PANEL, PIPING, 2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(margin)
	style.shadow_color = DROP
	style.shadow_size = 1
	style.shadow_offset = Vector2(5, 5)
	return style

## The cassette label: cream with red and blue stripes, title in marker.
static func header_box() -> StyleBox:
	var swipe := texture_box("marker/swipe_bar", Color.WHITE, 0, false)
	if swipe == null:
		var style := box(BG_HEADER)
		style.set_content_margin_all(0)
		return style
	swipe.texture_margin_left = 24   # nine-patch: the brush ends keep their shape
	swipe.texture_margin_right = 24
	swipe.texture_margin_top = 8
	swipe.texture_margin_bottom = 8
	swipe.content_margin_left = PAD + 4
	swipe.content_margin_right = 4
	return swipe

## A tiled art box from art/ui/street/<name>.png, or null when it is missing.
static func texture_box(name: String, tint: Color, margin: int, tile: bool = false) -> StyleBoxTexture:
	var path := STREET + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	style.modulate_color = tint
	if tile:
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.set_content_margin_all(margin)
	return style

## Gold rope chain in place of a plain line.
static func divider() -> Control:
	var path := STREET + "marker/swipe_thin.png"
	if not ResourceLoader.exists(path):
		return HSeparator.new()
	var strip := TextureRect.new()
	strip.texture = load(path)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE   # one marker stroke across the page
	strip.modulate = Color(1, 1, 1, 0.55)
	strip.custom_minimum_size = Vector2(0, 5)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return strip

static var _fonts := {}

## marker (titles), bungee (numbers, keys), lcd (pager), paper (newspaper).
static func font(kind: String) -> Font:
	if not _fonts.has(kind):
		var file: String = {"marker": "PermanentMarker", "bungee": "Bungee", "lcd": "VT323", "paper": "SpecialElite"}[kind]
		var path := "res://fonts/%s-Regular.ttf" % file
		_fonts[kind] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[kind]

## A piece of art from art/ui/street/<name>.png as a fixed-size decoration
## (tape, sticker, doodle), or null when the file is missing.
static func decal(name: String, height: float, angle_deg: float) -> TextureRect:
	var path := STREET + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex_size: Vector2 = t.texture.get_size()
	t.size = Vector2(height * tex_size.x / tex_size.y, height)
	t.pivot_offset = t.size * 0.5
	t.rotation_degrees = angle_deg
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func title_label(text: String) -> Label:
	var l := label(text, FONT_TITLE + 1, INK)
	l.add_theme_font_override("font", font("marker"))
	return l

static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
