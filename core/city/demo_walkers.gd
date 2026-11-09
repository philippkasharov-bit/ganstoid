## City batch C3e demo: pedestrians that pathfind through the real city by type.
##   civilian: public ground only (sidewalks, crosswalks, paths, parks), avoids
##             alleys, much more at night.
##   dark:     public ground, alleys at normal cost (addicts, thugs, low-wit NPCs).
##   local:    everything walkable incl. yards and gaps (knows the shortcuts).
## Each walks to a random spot within TRIP_M, then picks another. Demo only
## (real NPCs move in MG1); draws itself.
class_name DemoWalkers
extends Node2D

const SPEED := 6.0      # demo speed, m/s
const TRIP_M := 450.0
const SHARE := {"civilian": 0.75, "dark": 0.10, "local": 0.15}
const DOT := {"civilian": Color("1d4ed8"), "dark": Color("9333ea"), "local": Color("ea580c")}
const ALLEY_COST_DAY := 3.0
const ALLEY_COST_NIGHT := 8.0

var navs := {}   # kind -> CityNav ("civilian" and "dark" are public-layer maps, "local" the full map)
var rng := RandomNumberGenerator.new()
var walkers: Array[Dictionary] = []   # {kind: String, pos: Vector2, path: PackedVector2Array, i: int}
var night := false:
	set(v):
		night = v
		if navs.has("civilian"):
			navs["civilian"].alley_cost = ALLEY_COST_NIGHT if v else ALLEY_COST_DAY

func setup(public_nav: CityNav, dark_nav: CityNav, full_nav: CityNav) -> void:
	navs = {"civilian": public_nav, "dark": dark_nav, "local": full_nav}
	dark_nav.alley_cost = 1.0
	night = night   # applies the civilian alley cost

func spawn(centre: Vector2, count: int, seed_value: int = 7) -> void:
	rng.seed = seed_value
	walkers.clear()
	for k in count:
		var kind := _pick_kind()
		var p: Vector2 = navs[kind].closest(centre + Vector2(rng.randf_range(-400, 400), rng.randf_range(-400, 400)))
		walkers.append({"kind": kind, "pos": p, "path": PackedVector2Array(), "i": 0})

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

func _pick_kind() -> String:
	var r := rng.randf()
	for kind in SHARE:
		r -= SHARE[kind]
		if r < 0.0:
			return kind
	return "civilian"

func _new_trip(w: Dictionary) -> void:
	var nav: CityNav = navs[w["kind"]]
	var goal := nav.closest(w["pos"] + Vector2(rng.randf_range(-TRIP_M, TRIP_M), rng.randf_range(-TRIP_M, TRIP_M)))
	w["path"] = nav.path(w["pos"], goal)
	w["i"] = 1

func _draw() -> void:
	for w in walkers:
		var col: Color = DOT[w["kind"]]
		var path: PackedVector2Array = w["path"]
		if w["i"] < path.size():
			var rest := PackedVector2Array([w["pos"]])
			rest.append_array(path.slice(w["i"]))
			draw_polyline(rest, Color(col, 0.4), 1.5)
		draw_circle(w["pos"], 3.0, col)
