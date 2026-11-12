## MP3a: what stands at junctions and kerbs near you: traffic lights (live
## colour), stop signs with their white stop lines, bus stops with shelters.
## Only within RANGE_M of the camera, redrawn a few times a second.
extends Node2D

@export var world_driver_path: NodePath
const RANGE_M := 160.0
const REFRESH_S := 0.25
const POLE := Color("2b2b2e")
const LIGHTS := {"green": Color("3fd16b"), "yellow": Color("f2c230"), "red": Color("ea3b3b")}

var _world: World
var _left := 0.0

func _ready() -> void:
	_world = get_node(world_driver_path).world
	z_index = 3

func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_S
		queue_redraw()

func _draw() -> void:
	var j := TrafficSystem.junctions
	if j == null or get_viewport().get_camera_2d() == null:
		return
	var at := get_viewport().get_camera_2d().get_screen_center_position()
	var secs := float(_world.tick) / SimClock.TICKS_PER_SECOND
	for x in j.near(at, RANGE_M):
		for leg in x["legs"]:
			var into: Vector2 = leg[0]
			var w: float = leg[1]
			var right := Vector2(-into.y, into.x)
			var stop_at: Vector2 = x["c"] - into * (w * 0.5 + 3.0)
			var kerb := stop_at + right * (w * 0.5 + 0.6)
			if x["kind"] == "signal":
				draw_line(stop_at, stop_at + right * w * 0.5, Color(1, 1, 1, 0.85), 0.25)
				draw_rect(Rect2(kerb - Vector2(0.35, 0.35), Vector2(0.7, 0.7)), POLE)
				draw_circle(kerb, 0.25, LIGHTS[Junctions.light(x, into, secs)])
			else:
				draw_line(stop_at, stop_at + right * w * 0.5, Color(1, 1, 1, 0.9), 0.35)
				_octagon(kerb, 0.45, Color("c62828"))
	for b in j.bus_stops:
		if b["c"].distance_to(at) > RANGE_M:
			continue
		var d: Vector2 = b["dir"]
		var n := Vector2(-d.y, d.x)
		var c: Vector2 = b["c"] + n * 1.2
		draw_colored_polygon(PackedVector2Array([c - d * 1.8 - n * 0.6, c + d * 1.8 - n * 0.6, c + d * 1.8 + n * 0.6, c - d * 1.8 + n * 0.6]), Color("2a5d9f"))
		draw_circle(b["c"] - d * 2.6, 0.3, Color("2a5d9f"))

func _octagon(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(c + Vector2.from_angle(PI / 8.0 + i * PI / 4.0) * r)
	draw_colored_polygon(pts, col)
