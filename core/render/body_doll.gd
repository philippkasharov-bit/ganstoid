## HP1: the body figure in the health window, Zomboid-style: each part drawn as
## a simple shape, coloured by its condition (green fine, yellow, orange, red),
## white when bandaged, a red dot where it bleeds. Hover a part for its line.
class_name BodyDoll
extends Control

signal hover_part(part: String, at: Vector2)
signal hover_end

const W := 120.0
const H := 230.0
## part -> rect in a 120 x 230 figure (front view; the player's left is on screen right).
const SHAPES := {
	"head": Rect2(44, 4, 32, 34), "torso": Rect2(34, 42, 52, 78),
	"r_arm": Rect2(14, 44, 18, 66), "l_arm": Rect2(88, 44, 18, 66),
	"r_hand": Rect2(12, 112, 20, 18), "l_hand": Rect2(88, 112, 20, 18),
	"r_leg": Rect2(36, 124, 22, 100), "l_leg": Rect2(62, 124, 22, 100),
}

var body: Dictionary = {}
var _hovered := ""

func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP

static func condition_colour(hp: float) -> Color:
	if hp >= 0.85:
		return Color("6fae5b")
	if hp >= 0.6:
		return Color("d6c04f")
	return Color("d9893a") if hp >= 0.35 else Color("c0392b")

func _draw() -> void:
	for part in SHAPES:
		var r: Rect2 = SHAPES[part]
		var b: Dictionary = body.get(part, {"hp": 1.0, "wound": "", "bleeding": false, "bandaged": false})
		var fill: Color = Color(0.92, 0.92, 0.88) if b["bandaged"] else condition_colour(float(b["hp"]))
		var radius := 14 if part == "head" else 5
		var box := StyleBoxFlat.new()
		box.bg_color = Color(fill, 0.9)
		box.set_corner_radius_all(radius)
		box.border_color = UiTheme.ACCENT if part == _hovered else Color(0, 0, 0, 0.6)
		box.set_border_width_all(2 if part == _hovered else 1)
		draw_style_box(box, r)
		if b["bleeding"]:
			draw_circle(r.get_center(), 5.0, Color("b0101c"))
			draw_arc(r.get_center(), 7.0, 0, TAU, 16, Color(1, 1, 1, 0.8), 1.0)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var hit := ""
	for part in SHAPES:
		if SHAPES[part].has_point(event.position):
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
