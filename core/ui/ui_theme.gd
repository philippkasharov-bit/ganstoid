## UI4/UI16: the one visual language for every panel. UI16 dresses it in the
## 90s street look: black satin team-jacket panels, a cassette label for the
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

const FONT_SMALL := 12
const FONT_BODY := 14
const FONT_TITLE := 15
const HEADER_H := 30
const INK := Color(0.12, 0.11, 0.13)          # marker ink on the cassette label
const STREET := "res://art/ui/street/"
const PAD := 8
const ROW_H := 24

static func box(bg: Color, border: Color = FRAME, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_content_margin_all(PAD)
	return style

static func window_box() -> StyleBox:
	var satin := texture_box("tex/satin", Color(0.55, 0.55, 0.6), 1)
	if satin == null:
		var style := box(BG)
		style.set_content_margin_all(1)
		return style
	return satin

## The cassette label: cream with red and blue stripes, title in marker.
static func header_box() -> StyleBox:
	var label := texture_box("frames/cassette_strip", Color.WHITE, 0, false)
	if label == null:
		var style := box(BG_HEADER)
		style.set_content_margin_all(0)
		return style
	label.texture_margin_left = 14   # nine-patch: the torn ends keep their shape
	label.texture_margin_right = 14
	label.texture_margin_top = 12
	label.texture_margin_bottom = 12
	label.content_margin_left = PAD + 6
	label.content_margin_right = 6
	label.content_margin_top = 2
	return label

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
	var path := STREET + "frames/rope_strip.png"
	if not ResourceLoader.exists(path):
		return HSeparator.new()
	var strip := TextureRect.new()
	strip.texture = load(path)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_TILE   # the strip is cut 14 px tall, so it tiles at size
	strip.custom_minimum_size = Vector2(0, 14)
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

static func title_label(text: String) -> Label:
	var l := label(text, FONT_TITLE + 3, INK)
	l.add_theme_font_override("font", font("marker"))
	return l

static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
