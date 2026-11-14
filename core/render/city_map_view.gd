## MP1: the city map itself (CityMapWindow, N), Zomboid's paper map. Streets drawn by size, then
## markers: every shop and workshop (open now = bright, closed = dim, gone
## under = not shown), your home and your own businesses, and you. Wheel
## zooms round the mouse, drag pans; hovering a marker names it and its hours.
## Read-only: it draws World data and never writes it.
class_name CityMapView
extends Control

const ROAD_W := {"fwy": 7.0, "ramp": 3.0, "art": 4.0, "res": 2.0, "alley": 1.0}   # CityData tiers; service roads, paths and lot aisles are left off
const ROAD_COL := Color(0.86, 0.84, 0.78, 0.55)
const PAPER := Color(0.16, 0.16, 0.15)
const SHOP := Color(0.98, 0.78, 0.22)
const WORKSHOP := Color(0.36, 0.66, 0.95)
const MINE := Color(0.45, 0.85, 0.42)
const HOME := Color(0.95, 0.95, 0.95)
const ME := Color(0.95, 0.3, 0.25)
const MARK_PX := 4.0
const HOVER_PX := 9.0
const ZOOM_MIN := 0.06      # pixels per metre: the whole city
const ZOOM_MAX := 1.2       # a few blocks
const REFRESH_S := 1.0

var world: World
var city: CityData
var show_shops := true
var show_workshops := true
var show_mine := true
var zoom := 0.15
var centre := Vector2.ZERO  # map point in the middle of the view
var _marks: Array = []      # [map point, colour, label, bright]
var _hover := -1
var _drag := false
var _left := 0.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

## Centres on the player (called when the map opens).
func centre_on_player() -> void:
	var me := _me()
	if me != null:
		centre = me.position
	_collect()
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_S
		_collect()
		queue_redraw()

func _me() -> NPCData:
	var e: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	return e.get_component(ComponentNames.NPC) if e != null else null

## The markers to draw, from the buildings (each refresh: shops open and close).
func _collect() -> void:
	_marks.clear()
	var me := _me()
	if world == null or me == null:
		return
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.owner_npc_id == PlayerFactory.PLAYER_ENTITY_ID or b.id == me.home_building_id:
			if show_mine:
				_marks.append([b.position, HOME if b.id == me.home_building_id else MINE, "Your home" if b.id == me.home_building_id else "Yours: " + _name(b), true])
			continue
		var kind := ShopSystem.counter_kind(world, b.id)
		if kind == "" or (kind == "workshop" and not show_workshops) or (kind != "workshop" and not show_shops):
			continue
		var h := ShopSystem.hours_of(b.id, kind)
		var hours := "open 24 h" if h.y - h.x >= 24.0 else "%d:00-%d:00" % [int(h.x), int(h.y) % 24]
		_marks.append([b.position, WORKSHOP if kind == "workshop" else SHOP, "%s  (%s)" % [_name(b), hours], ShopSystem.is_open(world, b.id)])

static func _name(b: BuildingData) -> String:
	var kind := String(b.business_kind) if b.business_kind != &"" else "shop"
	return (String(b.trade) if b.trade != &"" else kind).capitalize()

func _to_screen(p: Vector2) -> Vector2:
	return (p - centre) * zoom + size * 0.5

func _to_map(s: Vector2) -> Vector2:
	return (s - size * 0.5) / zoom + centre

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if city != null:
		_draw_roads()
	for i in _marks.size():
		var m: Array = _marks[i]
		var s := _to_screen(m[0])
		if Rect2(Vector2.ZERO, size).grow(10).has_point(s):
			var col: Color = m[1] if m[3] else Color(m[1], 0.35)
			draw_circle(s, MARK_PX + (2.0 if i == _hover else 0.0), col)
			draw_arc(s, MARK_PX + 1.0, 0.0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
	_draw_me()
	if _hover >= 0 and _hover < _marks.size():
		var at := _to_screen(_marks[_hover][0]) + Vector2(10, -10)
		var text: String = _marks[_hover][2] + ("" if _marks[_hover][3] else "  - closed now")
		var font := get_theme_default_font()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_rect(Rect2(at + Vector2(-4, -15), Vector2(w + 8, 20)), Color(0, 0, 0, 0.8))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func _draw_roads() -> void:
	var view := Rect2(_to_map(Vector2.ZERO), size / zoom)
	for r in city.roads:
		var w: float = ROAD_W.get(r["tier"], 0.0)
		if w <= 0.0 or (zoom < 0.12 and w < 2.0):
			continue   # zoomed far out: the small streets would just be noise
		var pts: PackedVector2Array = r["pts"]
		if not view.grow(50.0).intersects(Rect2(pts[0], Vector2.ZERO).expand(pts[pts.size() - 1])):
			continue
		var out := PackedVector2Array()
		for p in pts:
			out.append(_to_screen(p))
		draw_polyline(out, ROAD_COL, maxf(1.0, w * zoom * 2.0))

func _draw_me() -> void:
	var me := _me()
	if me == null:
		return
	var s := _to_screen(me.position)
	draw_circle(s, 6.0, ME)
	draw_arc(s, 13.0, 0.0, TAU, 20, Color(ME, 0.6), 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var before := _to_map(event.position)
		zoom = clampf(zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_MIN, ZOOM_MAX)
		centre += before - _to_map(event.position)   # zoom round the mouse
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		accept_event()
	elif event is InputEventMouseMotion:
		if _drag:
			centre -= event.relative / zoom
		_hover = _nearest(event.position)
		queue_redraw()

func _nearest(s: Vector2) -> int:
	var best := -1
	var best_d := HOVER_PX
	for i in _marks.size():
		var d := _to_screen(_marks[i][0]).distance_to(s)
		if d < best_d:
			best_d = d
			best = i
	return best
