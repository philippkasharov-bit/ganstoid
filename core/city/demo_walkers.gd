## City batch C3 demo: pedestrians that pathfind through the real city: streets,
## alleys and the gaps between buildings. Each walks to a random spot within
## TRIP_M, then picks another. Demo only (real NPCs move in MG1); draws itself.
class_name DemoWalkers
extends Node2D

const SPEED := 6.0      # demo speed, m/s
const TRIP_M := 450.0

var nav: CityNav
var rng := RandomNumberGenerator.new()
var walkers: Array[Dictionary] = []   # {pos: Vector2, path: PackedVector2Array, i: int}

func spawn(centre: Vector2, count: int, seed_value: int = 7) -> void:
	rng.seed = seed_value
	walkers.clear()
	for k in count:
		var p := nav.closest(centre + Vector2(rng.randf_range(-400, 400), rng.randf_range(-400, 400)))
		walkers.append({"pos": p, "path": PackedVector2Array(), "i": 0})

func advance(delta: float) -> void:
	for w in walkers:
		if w["i"] >= w["path"].size():
			_new_trip(w)
			continue
		var target: Vector2 = w["path"][w["i"]]
		var step := SPEED * delta
		if w["pos"].distance_to(target) <= step:
			w["pos"] = target
			w["i"] += 1
		else:
			w["pos"] = w["pos"].move_toward(target, step)
	queue_redraw()

func _new_trip(w: Dictionary) -> void:
	var goal := nav.closest(w["pos"] + Vector2(rng.randf_range(-TRIP_M, TRIP_M), rng.randf_range(-TRIP_M, TRIP_M)))
	w["path"] = nav.path(w["pos"], goal)
	w["i"] = 1

func _draw() -> void:
	for w in walkers:
		var path: PackedVector2Array = w["path"]
		if w["i"] < path.size():
			var rest := PackedVector2Array([w["pos"]])
			rest.append_array(path.slice(w["i"]))
			draw_polyline(rest, Color(0.2, 0.55, 1.0, 0.45), 1.5)
		draw_circle(w["pos"], 3.0, Color("1d4ed8"))
