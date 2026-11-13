## HP2/HP3: the body figure in the health window, Zomboid-style: a smooth
## front-view figure split into Zomboid's 17 parts. A fine part is plain grey;
## a hurt part is filled by how bad its wound is (yellow minor, orange
## serious, red severe), the same colours as its line in the injury list.
## A bandage shows as white strips (yellowish once dirty), bleeding as a red
## drop, infection as a green edge. Click a part to read it; right-click to
## treat it. The figure faces you: its right side is on your left.
class_name BodyDoll
extends Control

signal part_clicked(part: String)
signal part_menu(part: String, at: Vector2)

const W := 150.0
const H := 310.0
const SEVERITY := [Color(0.34, 0.35, 0.38), Color("d8b23e"), Color("dd7b2e"), Color("c8322b")]
const INFECTED := Color("7fbf3f")
const OUTLINE := Color(0, 0, 0, 0.55)

static var SHAPES := _shapes()

var body: Dictionary = {}
var selected := ""
var _hovered := ""

func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP

## Right side is built on screen-left, then mirrored for the left side.
static func _shapes() -> Dictionary:
	var right := {
		"r_upper_arm": _capsule(Vector2(44, 64), Vector2(38, 104), 7.5),
		"r_forearm": _capsule(Vector2(37, 112), Vector2(31, 150), 6.5),
		"r_hand": _ellipse(Vector2(29, 165), Vector2(6.5, 9)),
		"r_thigh": _capsule(Vector2(64, 160), Vector2(62, 216), 10.5),
		"r_shin": _capsule(Vector2(62, 228), Vector2(61, 280), 8.0),
		"r_foot": [Vector2(55, 290), Vector2(67, 290), Vector2(68, 302), Vector2(47, 302), Vector2(49, 296)],
	}
	var out := {
		"head": _ellipse(Vector2(75, 24), Vector2(14, 18)),
		"neck": _capsule(Vector2(75, 43), Vector2(75, 50), 6.0),
		"torso_upper": [Vector2(55, 56), Vector2(95, 56), Vector2(104, 62), Vector2(101, 100), Vector2(49, 100), Vector2(46, 62)],
		"torso_lower": [Vector2(50, 103), Vector2(100, 103), Vector2(98, 134), Vector2(52, 134)],
		"groin": [Vector2(53, 137), Vector2(97, 137), Vector2(93, 150), Vector2(75, 157), Vector2(57, 150)],
	}
	for part in right:
		out[part] = right[part]
		out["l" + part.substr(1)] = right[part].map(func(p: Vector2) -> Vector2: return Vector2(W - p.x, p.y))
	for part in out:
		out[part] = PackedVector2Array(out[part])
	return out

static func _ellipse(c: Vector2, r: Vector2) -> Array:
	var pts: Array = []
	for i in 20:
		pts.append(c + Vector2(cos(i * TAU / 20.0) * r.x, sin(i * TAU / 20.0) * r.y))
	return pts

## A rounded limb from a to b.
static func _capsule(a: Vector2, b: Vector2, r: float) -> Array:
	var dir := (b - a).normalized()
	var ang := dir.angle()
	var pts: Array = []
	for i in 9:
		pts.append(b + Vector2.from_angle(ang - PI * 0.5 + PI * i / 8.0) * r)
	for i in 9:
		pts.append(a + Vector2.from_angle(ang + PI * 0.5 + PI * i / 8.0) * r)
	return pts

## The colour of a part (and of its line in the list), by severity.
static func colour_of(b: Dictionary) -> Color:
	return SEVERITY[BodyParts.severity(b)]

func _draw() -> void:
	for part in SHAPES:
		var pts: PackedVector2Array = SHAPES[part]
		var b: Dictionary = body.get(part, BodyParts.fresh())
		var fill := colour_of(b)
		draw_colored_polygon(pts, fill.lightened(0.12) if part == _hovered else fill)
		if b["bandaged"]:
			_bandage(pts, BodyParts.dirty(b))
		var infected := float(b.get("infection", 0.0)) >= 1.0
		var edge := UiTheme.ACCENT if part == selected else (INFECTED if infected else OUTLINE)
		draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 2.0 if edge != OUTLINE else 1.0, true)
		if b["bleeding"]:
			_drop(_centre(pts))

## Strips across the part (yellowed when the dressing is dirty).
func _bandage(pts: PackedVector2Array, is_dirty: bool) -> void:
	var r := _bounds(pts)
	var col := Color(0.82, 0.74, 0.5, 0.9) if is_dirty else Color(0.96, 0.96, 0.94, 0.92)
	var y := r.position.y + 4.0
	while y < r.end.y - 3.0:
		var hits := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(r.position.x - 2, y), Vector2(r.end.x + 2, y + 2)]), pts)
		for seg in hits:
			draw_polyline(seg, col, 3.0)
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

## The part under a point of this control, or "".
static func part_at(local: Vector2) -> String:
	for part in SHAPES:
		if Geometry2D.is_point_in_polygon(local, SHAPES[part]):
			return part
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := part_at(event.position)
		if hit != _hovered:
			_hovered = hit
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hit != "" else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var hit := part_at(event.position)
		if hit == "":
			return
		part_clicked.emit(hit)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			part_menu.emit(hit, get_global_mouse_position())

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered != "":
		_hovered = ""
		queue_redraw()
