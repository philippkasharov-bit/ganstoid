## UI7: a coloured ring at the feet of everyone near you who is something to
## you (Relation: crew, staff, police, gang, friend, scared, enemy); strangers
## get none. Point at someone and a name card shows who they are to you.
## Read-only.
class_name RelationView
extends Control

const RANGE_M := 30.0
const RING := Vector2(16, 7)     # px half-width and half-height of the ring
const HOVER_PX := 26.0
const REFRESH_S := 0.15

var _world: World
var _marks: Array = []   # [position, colour, name, label]
var _t := 0.0

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH_S
		_scan()
	queue_redraw()

func _scan() -> void:
	_marks.clear()
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	for id in _world.spatial_index.query_nearby(me.position):
		var e: Entity = _world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n == null or n == me or n.indoors or n.position.distance_to(me.position) > RANGE_M:
			continue
		var rel := Relation.of(_world, state, n)
		if not rel.is_empty():
			_marks.append([n.id, rel[0], n.display_name, rel[1]])

func _draw() -> void:
	var mouse := get_local_mouse_position()
	var card: Array = []
	for m in _marks:
		var e: Entity = _world.entities.get(m[0])
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n == null:
			continue
		var at := ScreenMap.to_screen(get_viewport(), n.position, 0.05)
		var col: Color = m[1]
		_ellipse(at, RING, Color(col, 0.85), 2.5)
		_ellipse(at, RING * 0.7, Color(col, 0.25), 0.0)
		var head := ScreenMap.to_screen(get_viewport(), n.position, 1.8)
		if mouse.distance_to(at) < HOVER_PX or mouse.distance_to(head) < HOVER_PX:
			card = [head, m]
	if not card.is_empty():
		_card(card[0], card[1])

func _ellipse(c: Vector2, r: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	if width > 0.0:
		draw_polyline(pts, col, width, true)
	else:
		draw_colored_polygon(pts, col)

## Name and what they are to you, over their head.
func _card(at: Vector2, m: Array) -> void:
	var font := ThemeDB.fallback_font
	var name: String = m[2] if m[2] != "" else "Someone"
	var label: String = m[3]
	var w := maxf(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 18.0
	var box := Rect2(at - Vector2(w * 0.5, 52), Vector2(w, 42))
	draw_rect(box, Color(0.06, 0.07, 0.09, 0.9))
	draw_rect(Rect2(box.position, Vector2(4, box.size.y)), m[1])
	draw_string(font, box.position + Vector2(10, 18), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(font, box.position + Vector2(10, 35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(m[1]).lightened(0.3))
