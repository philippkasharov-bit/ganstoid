## MP1: the city map itself (CityMapWindow, N), Zomboid's paper map. Streets drawn by size, then
## markers: shops and workshops (open now = bright, closed = dim, gone
## under = not shown), your home and your own businesses, and you. Wheel
## zooms round the mouse, drag pans; hovering a marker names it and its hours.
## MP2: fog of war. Only what you have explored shows (ExplorationSystem):
## places there, the dealers and fixers you have met (each with a letter),
## the blocks a gang holds washed in its colour (a gang's turf grows on the
## map as you walk its edges), your job's target, and the rest under fog.
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
const DEALER := Color(0.95, 0.35, 0.35)
const FIXER := Color(0.75, 0.5, 0.95)
const JOB := Color(1.0, 0.55, 0.1)
const FOG := Color(0.07, 0.07, 0.08, 0.88)
const TURF_ALPHA := 0.32
const MARK_PX := 4.0
const HOVER_PX := 9.0
const ZOOM_MIN := 0.06      # pixels per metre: the whole city
const ZOOM_MAX := 1.2       # a few blocks
const REFRESH_S := 1.0
const OPEN_ZOOM := 0.55     # MP2: opens on your neighbourhood, not the whole (mostly fogged) city

var world: World
var city: CityData
var show_shops := true
var show_workshops := true
var show_mine := true
var show_people := true     # MP2: dealers and fixers you know
var show_turf := true
var _fog := ImageTexture.new()
var _fog_img: Image
var _turf: Array = []       # [poly, colour, label] of explored blocks someone holds
var zoom := 0.15
var centre := Vector2.ZERO  # map point in the middle of the view
var _marks: Array = []      # [map point, colour, label, bright]
var _hover := -1
var _mouse := Vector2(-1000, -1000)
var _drag := false
var _left := 0.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

## Centres on the player (called when the map opens) at the neighbourhood zoom.
func centre_on_player() -> void:
	zoom = OPEN_ZOOM
	var me := _me()
	if me != null:
		centre = me.position
	_keep_in_city()
	_collect()
	queue_redraw()

## BUG-4: the view stops at the city's edge instead of showing empty dark space;
## zoomed out past the whole city, it stays centred on it.
func _keep_in_city() -> void:
	if city == null or city.size_m <= 0.0:
		return
	var half := size * 0.5 / zoom
	for axis in 2:
		centre[axis] = city.size_m * 0.5 if half[axis] * 2.0 >= city.size_m else clampf(centre[axis], half[axis], city.size_m - half[axis])

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_S
		_collect()
		queue_redraw()

func _waypoint() -> Vector2:
	var e: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	return (e.get_component(ComponentNames.PLAYER_STATE) as PlayerStateData).waypoint if e != null else Vector2.INF

func _me() -> NPCData:
	var e: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	return e.get_component(ComponentNames.NPC) if e != null else null

## The markers to draw (each refresh: shops open and close, you explore).
func _collect() -> void:
	_marks.clear()
	_turf.clear()
	var me := _me()
	if world == null or me == null:
		return
	var state: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if b.owner_npc_id == PlayerFactory.PLAYER_ENTITY_ID or b.id == me.home_building_id:
			if show_mine:
				_marks.append([b.position, HOME if b.id == me.home_building_id else MINE, "Your home" if b.id == me.home_building_id else "Yours: " + _name(b), true, "H" if b.id == me.home_building_id else ""])
			continue
		var kind := ShopSystem.counter_kind(world, b.id)
		if kind == "" or (kind == "workshop" and not show_workshops) or (kind != "workshop" and not show_shops):
			continue
		if not ExplorationSystem.explored(state, b.position):
			continue   # MP2: not found yet
		var h := ShopSystem.hours_of(b.id, kind)
		var hours := "open 24 h" if h.y - h.x >= 24.0 else "%d:00-%d:00" % [int(h.x), int(h.y) % 24]
		var what := "fix weapons, sells tools" if kind == "workshop" else "food, drink, bandages"
		_marks.append([b.position, WORKSHOP if kind == "workshop" else SHOP, "%s  (%s): %s" % [_name(b), hours, what], ShopSystem.is_open(world, b.id), ""])
	if show_people:
		for id in state.known:
			var e: Entity = world.entities.get(id)
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n == null or n.is_down:
				continue
			if state.known[id] == "dealer":
				_marks.append([n.position, DEALER, "Street dealer: weed; guns once you're a Hustler", true, "$"])
			else:
				_marks.append([n.position, FIXER, "Fixer: E > Ask for work", true, "F"])
	var target: Variant = JobSystem.target_point(world, state)
	if target != null:
		_marks.append([target, JOB, "Your job", true, "!"])
	if show_turf:
		_collect_turf(state)
	_paint_fog(state)

## MP2: explored blocks someone holds, in the holder's colour.
func _collect_turf(state: PlayerStateData) -> void:
	var t := TerritorySystem.data(world)
	var h := Hoods.data()
	if t == null or h == null:
		return
	for c in t.cells:
		var owner := TerritorySystem.controller(t, c)
		if owner == &"" or not Hoods.is_block(c):
			continue
		var blk := h.block(c)
		if blk.is_empty() or not ExplorationSystem.explored(state, blk["c"]):
			continue
		var who := "Your turf" if owner == TerritorySystem.PLAYER else "%s turf" % _gang_name(owner)
		_turf.append([blk["poly"], TerritorySystem.GANG_COLORS.get(owner, Color.GRAY), "%s: %s" % [blk.get("name", "a block"), who]])

func _gang_name(id: StringName) -> String:
	var e: Entity = world.entities.get(id)
	var g: GangData = e.get_component(ComponentNames.GANG) if e != null else null
	return g.display_name if g != null else String(id)

## MP2: the fog as one small picture (a pixel per explored cell), stretched over the city.
func _paint_fog(state: PlayerStateData) -> void:
	var n := ExplorationSystem.GRID
	if _fog_img == null:
		_fog_img = Image.create(n, n, false, Image.FORMAT_LA8)
	_fog_img.fill(Color(0, 0, 0, 1))
	if state.explored.size() == n * n / 8:
		for i in n * n:
			if state.explored[i >> 3] & (1 << (i & 7)):
				_fog_img.set_pixel(i % n, i / n, Color(0, 0, 0, 0))
	_fog.set_image(_fog_img)

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
	for blk in _turf:
		var pts := PackedVector2Array()
		for q in (blk[0] as PackedVector2Array):
			pts.append(_to_screen(q))
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(blk[1], TURF_ALPHA))
	var n := float(ExplorationSystem.GRID) * ExplorationSystem.CELL_M
	draw_texture_rect(_fog, Rect2(_to_screen(Vector2.ZERO), Vector2(n, n) * zoom), false, FOG)
	var font := get_theme_default_font()
	for i in _marks.size():
		var m: Array = _marks[i]
		var s := _to_screen(m[0])
		if Rect2(Vector2.ZERO, size).grow(10).has_point(s):
			var col: Color = m[1] if m[3] else Color(m[1], 0.35)
			var letter: String = m[4]
			var r := MARK_PX + (2.0 if i == _hover else 0.0) + (3.0 if letter != "" else 0.0)
			draw_circle(s, r, col)
			draw_arc(s, r + 1.0, 0.0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
			if letter != "":
				draw_string(font, s + Vector2(-4, 4), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0))
	_draw_me()
	var wp := _waypoint()
	if wp != Vector2.INF:   # MM1: the GPS flag
		var ws := _to_screen(wp)
		draw_line(ws, ws + Vector2(0, -18), Color.WHITE, 2.0)
		draw_colored_polygon(PackedVector2Array([ws + Vector2(0, -18), ws + Vector2(12, -14), ws + Vector2(0, -10)]), MiniMap.GPS)
	var text := ""
	var at := _mouse + Vector2(12, -10)
	if _hover >= 0 and _hover < _marks.size():
		at = _to_screen(_marks[_hover][0]) + Vector2(10, -10)
		text = _marks[_hover][2] + ("" if _marks[_hover][3] else "  - closed now")
	else:
		var p := _to_map(_mouse)
		for blk in _turf:
			if Geometry2D.is_point_in_polygon(p, blk[0]):
				text = blk[2]   # MP2: whose block this is
				break
	if text != "":
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
		_keep_in_city()
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		set_waypoint(_to_map(event.position))   # MM1: the GPS
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		accept_event()
	elif event is InputEventMouseMotion:
		if _drag:
			centre -= event.relative / zoom
			_keep_in_city()
		_hover = _nearest(event.position)
		_mouse = event.position
		queue_redraw()

## MM1: right-click: the GPS points here (right-click it again to clear).
func set_waypoint(at: Vector2) -> void:
	var p: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	state.waypoint = Vector2.INF if state.waypoint != Vector2.INF and state.waypoint.distance_to(at) * zoom < 12.0 else at
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
