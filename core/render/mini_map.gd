## MM1: the minimap, bottom right (RP-server style): the streets round you,
## turned so up on it is up on your screen, the places you have found
## (shops, dealers $, fixers F), your job (!), and the GPS: a yellow line
## along the streets to your waypoint (right-click the big map, N), or to
## your job when you have no waypoint. Read-only.
class_name MiniMap
extends Control

const SIZE := 190.0
const RANGE_M := 160.0            # map metres from the middle to the edge
const ROADS_M := 260.0            # roads cached round this point
const RECACHE_M := 70.0
const ROUTE_EVERY_S := 1.5
const REDRAW_S := 0.1
const ROAD_W := {"fwy": 5.0, "ramp": 2.5, "art": 3.5, "res": 2.0, "alley": 1.0}
const GPS := Color(1.0, 0.82, 0.15)

var city: CityData
var _world: World
var _roads: Array = []            # [PackedVector2Array, width]
var _cached_at := Vector2.INF
var _route := PackedVector2Array()
var _route_left := 0.0
var _route_key := Vector4.INF
var _redraw := 0.0

func setup(world: World, c: CityData) -> void:
	_world = world
	city = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)

func _process(delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var want: bool = p != null and GameRules.of(_world) != null and SimNav.active != null and SimNav.active.usable() and HudLayout.shown("minimap")
	UiMotion.fade(self, want, delta, Vector2(0, 1))   # UI6: O hides it
	if not want:
		return
	var view := get_viewport_rect().size
	position = HudLayout.place(self, "minimap", Vector2(view.x - SIZE - UiTheme.MARGIN, view.y - SIZE - UiTheme.MARGIN)) + UiMotion.shift(self)
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	if _cached_at == Vector2.INF or me.position.distance_to(_cached_at) > RECACHE_M:
		_cache_roads(me.position)
	_route_left -= delta
	var goal: Variant = gps_goal(_world, state)
	if goal == null:
		_route = PackedVector2Array()
	elif _route_left <= 0.0:
		_route_left = ROUTE_EVERY_S
		var key := Vector4(roundf(me.position.x / 20.0), roundf(me.position.y / 20.0), (goal as Vector2).x, (goal as Vector2).y)
		if key != _route_key:
			_route_key = key
			_route = gps_route(me.position, goal)
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = REDRAW_S
		queue_redraw()

## Where the GPS points: your waypoint, else your job, else nowhere.
static func gps_goal(world: World, state: PlayerStateData) -> Variant:
	if state.waypoint != Vector2.INF:
		return state.waypoint
	return JobSystem.target_point(world, state)

## The way along the streets, from you to `goal` (straight line when there is no road graph).
static func gps_route(from: Vector2, goal: Vector2) -> PackedVector2Array:
	var line := DriveSystem.graph.route(from, goal) if DriveSystem.graph != null else PackedVector2Array()
	if line.is_empty():
		return PackedVector2Array([from, goal])
	line.insert(0, from)
	line.append(goal)
	return line

func _cache_roads(at: Vector2) -> void:
	_cached_at = at
	_roads.clear()
	if city == null:
		return
	var box := Rect2(at - Vector2(ROADS_M, ROADS_M), Vector2(ROADS_M, ROADS_M) * 2.0)
	for r in city.roads:
		var w: float = ROAD_W.get(r["tier"], 0.0)
		var pts: PackedVector2Array = r["pts"]
		if w > 0.0 and box.intersects(Rect2(pts[0], Vector2.ZERO).expand(pts[pts.size() - 1]).grow(40.0)):
			_roads.append([pts, w])

## Map point -> minimap pixel: centred on you, turned with the camera.
func _to_mini(p: Vector2, me: Vector2, turn: float) -> Vector2:
	return Vector2(SIZE, SIZE) * 0.5 + ((p - me) * (SIZE * 0.5 / RANGE_M)).rotated(turn)

func _turn() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var f := -cam.global_basis.z
	var fwd := Vector2(f.x, f.z)
	return 0.0 if fwd.length() < 0.01 else -fwd.angle() - PI * 0.5   # screen-up = where the camera looks

func _draw() -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var turn := _turn()
	var c := Vector2(SIZE, SIZE) * 0.5
	var r := SIZE * 0.5
	draw_circle(c, r + 3.0, Color(0, 0, 0, 0.75))
	draw_circle(c, r, Color(0.12, 0.13, 0.12, 0.92))
	var k := SIZE * 0.5 / RANGE_M
	for road in _roads:
		var line := PackedVector2Array()
		for q in (road[0] as PackedVector2Array):
			line.append(_to_mini(q, me.position, turn))
		draw_polyline(line, Color(0.72, 0.72, 0.68, 0.55 if ExplorationSystem.explored(state, (road[0] as PackedVector2Array)[0]) else 0.18), maxf(1.0, road[1] * k * 1.6))
	if _route.size() >= 2:
		var line := PackedVector2Array()
		for q in _route:
			line.append(_to_mini(q, me.position, turn))
		draw_polyline(line, GPS, 3.0)
	for m in _marks(state, me):
		var s := _to_mini(m[0], me.position, turn)
		if s.distance_to(c) <= r - 6.0:
			draw_circle(s, 5.0, m[1])
			if m[2] != "":
				draw_string(get_theme_default_font(), s + Vector2(-3.5, 4), m[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	var hot := _draw_police(me, turn, c, r)   # CH1
	var goal: Variant = gps_goal(_world, state)
	if goal != null:
		var s := _to_mini(goal, me.position, turn)
		if s.distance_to(c) > r - 8.0:
			s = c + (s - c).normalized() * (r - 8.0)   # off the edge: pinned to the rim, pointing the way
		var pulse := fmod(Time.get_ticks_msec() / 900.0, 1.0)   # UI6: the waypoint pulses
		draw_arc(s, 6.0 + pulse * 10.0, 0.0, TAU, 20, Color(GPS, 1.0 - pulse), 2.0)
		draw_circle(s, 6.0, GPS)
		draw_circle(s, 3.0, Color.BLACK)
		var d := roundi(me.position.distance_to(goal))
		var label := "GPS %d m" % d
		var f := get_theme_default_font()
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var at := Vector2((SIZE - lw) * 0.5, SIZE - 24)
		draw_rect(Rect2(at + Vector2(-4, -12), Vector2(lw + 8, 16)), Color(0, 0, 0, 0.7))
		draw_string(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GPS)
	var face := (state.aim_point - me.position).rotated(turn).angle() if state.aim_point != me.position else -PI * 0.5
	var tip := c + Vector2.from_angle(face) * 9.0
	draw_colored_polygon(PackedVector2Array([tip, c + Vector2.from_angle(face + 2.5) * 6.0, c + Vector2.from_angle(face - 2.5) * 6.0]), Color(0.95, 0.3, 0.25))
	var rim := Color(1, 1, 1, 0.18)
	if hot:   # CH1: they're after you: the rim flashes red and blue
		rim = Color(0.9, 0.15, 0.15) if int(Time.get_ticks_msec() / 300) % 2 == 0 else Color(0.2, 0.35, 0.95)
	draw_arc(c, r, 0.0, TAU, 48, rim, 3.0 if hot else 1.5)

## CH1: police after you: a red circle where they are searching, flashing
## red/blue dots for the officers and the chasing car. True if anyone is.
func _draw_police(me: NPCData, turn: float, c: Vector2, r: float) -> bool:
	var cops := _world.find_system(CopAISystem) as CopAISystem
	var traffic := _world.find_system(TrafficSystem) as TrafficSystem
	var flash := Color(0.9, 0.15, 0.15) if int(Time.get_ticks_msec() / 300) % 2 == 0 else Color(0.2, 0.35, 0.95)
	var any := false
	var k := SIZE * 0.5 / RANGE_M
	if cops != null:
		for h in cops.hunters():
			any = true
			if h[2]:
				var z := _to_mini(h[1], me.position, turn)
				if z.distance_to(c) < r + CopAISystem.SEARCH_RADIUS_M * k:
					draw_circle(z, CopAISystem.SEARCH_RADIUS_M * k * 1.4, Color(0.9, 0.15, 0.15, 0.22))
			var s := _to_mini(h[0], me.position, turn)
			if s.distance_to(c) <= r - 4.0:
				draw_circle(s, 4.0, flash)
	if traffic != null and traffic.chasing():
		any = true
		var s := _to_mini(traffic.chaser_at(), me.position, turn)
		if s.distance_to(c) <= r - 4.0:
			draw_rect(Rect2(s - Vector2(5, 3), Vector2(10, 6)), flash)
	return any

## [point, colour, letter] of what you know near you.
func _marks(state: PlayerStateData, me: NPCData) -> Array:
	var out: Array = []
	for id in state.known:
		var e: Entity = _world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and not n.is_down and n.position.distance_to(me.position) <= RANGE_M:
			out.append([n.position, CityMapView.DEALER if state.known[id] == "dealer" else CityMapView.FIXER, "$" if state.known[id] == "dealer" else "F"])
	var job: Variant = JobSystem.target_point(_world, state)
	if job != null:
		out.append([job, CityMapView.JOB, "!"])
	for id in _world.spatial_index.query_nearby(me.position):
		var e: Entity = _world.entities.get(id)
		var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
		if b != null and b.position.distance_to(me.position) <= RANGE_M and ShopSystem.counter_kind(_world, id) != "":
			out.append([b.position, CityMapView.SHOP if ShopSystem.counter_kind(_world, id) != "workshop" else CityMapView.WORKSHOP, ""])
	return out
