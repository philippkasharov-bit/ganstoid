## UI4: the one visual language for every panel (Zomboid-style: worn dark
## slate, thin light frame, muted text, one warm accent). Panels read colours,
## sizes and boxes from here so restyling the game is a one-file change.
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
const HEADER_H := 26
const PAD := 8
const ROW_H := 24

static func box(bg: Color, border: Color = FRAME, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_content_margin_all(PAD)
	return style

static func window_box() -> StyleBoxFlat:
	var style := box(BG)
	style.set_content_margin_all(1)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	return style

static func header_box() -> StyleBoxFlat:
	var style := box(BG_HEADER)
	style.border_width_bottom = 1
	style.set_content_margin_all(0)
	style.content_margin_left = PAD
	return style

static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
