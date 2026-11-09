## MG1b: routes sim movers along the real city's navmeshes instead of straight
## lines through buildings. Installed once per game (or per check) for the active
## district; when nothing is installed, movers fall back to straight lines (pure
## logic checks that don't need geometry).
##   layer "public": civilians (sidewalks, crosswalks, paths, parks, alleys)
##   layer "full":   cops, crew, dealers (everything walkable)
## A mover's own doorway may sit on private ground (their yard): civilians reach
## public ground and leave it again via a short route on the full mesh.
class_name SimNav
extends RefCounted

const LAST_HOP_M := 40.0   # straight walk allowed from the navmesh to the actual goal
const REPATH_M := 3.0      # re-plan when the goal has moved this far (chases)

static var active: SimNav = null

var navs := {}            # layer -> CityNav
var collision: CityCollision
var _plans := {}          # mover_id -> {goal: Vector2, layer: String, pts: PackedVector2Array, i: int}

## Loads both navmeshes around the district (takes several seconds) and makes
## this the router every mover uses.
static func install(city: CityData, centre: Vector2, radius: float) -> SimNav:
	uninstall()
	var nav := SimNav.new()
	nav.navs = {"full": CityNav.new(centre, radius + 200.0, "full"), "public": CityNav.new(centre, radius + 200.0, "public")}
	nav.navs["public"].alley_cost = 3.0   # civilians avoid alleys (night raises this later)
	nav.collision = CityCollision.new(city)
	active = nav
	return nav

static func uninstall() -> void:
	if active != null:
		for n in active.navs.values():
			n.release()
	active = null

## Nearest walkable point on `layer` (wander targets must be reachable).
func snap(p: Vector2, layer: String) -> Vector2:
	return navs[layer].closest(p)

## Moves one mover `speed * delta` metres along its route to `goal`.
func step(mover_id: StringName, pos: Vector2, goal: Vector2, speed: float, delta: float, layer: String) -> Vector2:
	var plan: Dictionary = _plans.get(mover_id, {})
	if plan.is_empty() or plan["layer"] != layer or plan["goal"].distance_to(goal) > REPATH_M:
		plan = _plan(pos, goal, layer)
		_plans[mover_id] = plan
	var budget := speed * delta
	var pts: PackedVector2Array = plan["pts"]
	while budget > 0.0 and plan["i"] < pts.size():
		var target: Vector2 = pts[plan["i"]]
		var d := pos.distance_to(target)
		if d <= budget:
			pos = target
			budget -= d
			plan["i"] += 1
		else:
			pos = pos.move_toward(target, budget)
			budget = 0.0
	return pos

func forget(mover_id: StringName) -> void:
	_plans.erase(mover_id)

## Player movement: slide along walls instead of walking through them.
func slide(from: Vector2, delta: Vector2) -> Vector2:
	return collision.slide(from, delta)

func _plan(pos: Vector2, goal: Vector2, layer: String) -> Dictionary:
	var nav: CityNav = navs[layer]
	var start := nav.closest(pos)
	var end := nav.closest(goal)
	var pts := nav.path(start, end)
	if pts.is_empty():
		pts = navs["full"].path(pos, goal)   # off this layer's loaded mesh: any walkable way
	elif layer != "full":
		# Getting on/off public ground crosses the mover's own yard: route those
		# hops on the full mesh so they go around houses, not through them.
		var head: PackedVector2Array = navs["full"].path(pos, start)
		if end.distance_to(goal) <= LAST_HOP_M:
			pts.append_array(navs["full"].path(end, goal))
		head.append_array(pts)
		pts = head
	if pts.is_empty():
		pts = PackedVector2Array([goal])     # nowhere on any mesh: straight line
	return {"goal": goal, "layer": layer, "pts": pts, "i": 0}
