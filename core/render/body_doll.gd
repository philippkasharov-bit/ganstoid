## HP2: the body figure in the health window, Zomboid-style: a front-view
## human outline split into Zomboid's 17 parts. A fine part is plain grey;
## a hurt part is filled by how bad its wound is (yellow minor, orange
## serious, red severe), the same colours as its line in the injury list.
## A bandage shows as white strips over the colour (grey strips once dirty),
## bleeding as a red drop, infection as a sick green edge. Hover a part for
## its line. The figure faces you: its right side is on your left.
class_name BodyDoll
extends Control

signal hover_part(part: String, at: Vector2)
signal hover_end

const W := 140.0
const H := 300.0
const FINE := Color(0.36, 0.37, 0.4)
const SEVERITY := [Color(0.36, 0.37, 0.4), Color("d8b23e"), Color("dd7b2e"), Color("c8322b")]
const INFECTED := Color("7fbf3f")
const OUTLINE := Color(0, 0, 0, 0.7)

static var SHAPES := _shapes()

var body: Dictionary = {}
var _hovered := ""

func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP

## Right side on screen-left; the left side is mirrored.
static func _shapes() -> Dictionary:
	var right := {
		"r_upper_arm": [Vector2(34, 52), Vector2(48, 52), Vector2(45, 100), Vector2(31, 98)],
		"r_forearm": [Vector2(31, 98), Vector2(45, 100), Vector2(41, 146), Vector2(28, 144)],
		"r_hand": [Vector2(27, 144), Vector2(41, 146), Vector2(40, 166), Vector2(24, 164)],
		"r_thigh": [Vector2(49, 150), Vector2(69, 153), Vector2(66, 214), Vector2(50, 214)],
		"r_shin": [Vector2(50, 214), Vector2(66, 214), Vector2(64, 279), Vector2(52, 279)],
		"r_foot": [Vector2(51, 279), Vector2(64, 279), Vector2(66, 295), Vector2(43, 295)],
	}
	var out := {
		"head": _ellipse(Vector2(70, 24), Vector2(13, 17)),
		"neck": [Vector2(63, 40), Vector2(77, 40), Vector2(77, 50), Vector2(63, 50)],
		"torso_upper": [Vector2(48, 50), Vector2(92, 50), Vector2(95, 96), Vector2(45, 96)],
		"torso_lower": [Vector2(45, 96), Vector2(95, 96), Vector2(92, 132), Vector2(48, 132)],
		"groin": [Vector2(48, 132), Vector2(92, 132), Vector2(80, 152), Vector2(60, 152)],
	}
	for part in right:
		out[part] = PackedVector2Array(right[part])
		out["l" + part.substr(1)] = PackedVector2Array(right[part].map(func(p: Vector2) -> Vector2: return Vector2(W - p.x, p.y)))
	for part in out:
		out[part] = PackedVector2Array(out[part])
	return out

static func _ellipse(c: Vector2, r: Vector2) -> Array:
	var pts: Array = []
	for i in 16:
		pts.append(c + Vector2(cos(i * TAU / 16.0) * r.x, sin(i * TAU / 16.0) * r.y))
	return pts

## The colour of a part (and of its line in the list), by severity.
static func colour_of(b: Dictionary) -> Color:
	return SEVERITY[BodyParts.severity(b)]

func _draw() -> void:
	for part in SHAPES:
		var pts: PackedVector2Array = SHAPES[part]
		var b: Dictionary = body.get(part, BodyParts.fresh())
		draw_colored_polygon(pts, colour_of(b))
		if b["bandaged"]:
			_bandage(pts, BodyParts.dirty(b))
		var edge := INFECTED if float(b.get("infection", 0.0)) >= 1.0 else (UiTheme.ACCENT if part == _hovered else OUTLINE)
		draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 2.0 if edge != OUTLINE else 1.0, true)
		if b["bleeding"]:
			_drop(_centre(pts))

## White strips across the part (greyed when the dressing is dirty).
func _bandage(pts: PackedVector2Array, is_dirty: bool) -> void:
	var r := _bounds(pts)
	var col := Color(0.72, 0.68, 0.6, 0.9) if is_dirty else Color(0.96, 0.96, 0.94, 0.92)
	var y := r.position.y + 3.0
	while y < r.end.y - 2.0:
		draw_line(Vector2(r.position.x + 2.0, y), Vector2(r.end.x - 2.0, y + 3.0), col, 3.0)
		y += 7.0

func _drop(c: Vector2) -> void:
	draw_circle(c + Vector2(0, 2), 4.0, Color("8e0f16"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-3.4, 1), c + Vector2(0, -6), c + Vector2(3.4, 1)]), Color("8e0f16"))

static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r

static func _centre(pts: PackedVector2Array) -> Vector2:
	return _bounds(pts).get_center()

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var hit := ""
	for part in SHAPES:
		if Geometry2D.is_point_in_polygon(event.position, SHAPES[part]):
			hit = part
	if hit != _hovered:
		_hovered = hit
		queue_redraw()
		if hit != "":
			hover_part.emit(hit, get_global_mouse_position())
		else:
			hover_end.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered != "":
		_hovered = ""
		hover_end.emit()
		queue_redraw()
