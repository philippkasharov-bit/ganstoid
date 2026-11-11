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
const SHORT_M := 14.0      # hops this short go straight when no building is in the way
const LINE_RADIUS_M := 0.15  # doors sit right against their wall: a full body radius would call every doorway blocked
## A route query costs about 2 ms. Civilians share this many per tick; cops, crew
## and dealers (layer "full") are never made to wait.
const PUBLIC_PLANS_PER_TICK := 1
const PUBLIC_PLAN_EVERY_TICKS := 2   # a 5-10 ms query every tick is half a frame; every other tick leaves room
const MAX_LANE_M := 0.35   # under the 0.4 m the navmesh keeps from every wall
const UNREACHED_M := 2.0   # a route ending further than this from its goal did not get there

static var active: SimNav = null

var navs := {}            # layer -> CityNav
var collision: CityCollision
var _plans := {}          # mover_id -> {goal: Vector2, layer: String, pts: PackedVector2Array, i: int}

## Loads both navmeshes around the district (takes several seconds) and makes
## this the router every mover uses.
static func install(city: CityData, centre: Vector2, radius: float) -> SimNav:
	uninstall()
	var nav := SimNav.new()
	nav.navs = {"full": CityNav.new(centre, radius + 200.0, "full"),
		"public": CityNav.new(centre, radius + 200.0, "public", 3.0)}   # civilians avoid alleys (night raises this later)
	nav.collision = CityCollision.new(city)
	active = nav
	return nav

static func uninstall() -> void:
	if active != null:
		for n in active.navs.values():
			n.release()
	active = null

## Both navmeshes synced (Godot syncs them in the background after install/refocus).
func is_ready() -> bool:
	for n in navs.values():
		if not n.is_ready():
			return false
	return true

## Nearest walkable point on `layer` (wander targets must be reachable).
func snap(p: Vector2, layer: String) -> Vector2:
	return navs[layer].closest(p)

## Moves one mover `speed * delta` metres along its route to `goal`.
func step(mover_id: StringName, pos: Vector2, goal: Vector2, speed: float, delta: float, layer: String) -> Vector2:
	var plan: Dictionary = _plans.get(mover_id, {})
	if plan.is_empty() or plan["layer"] != layer or plan["goal"].distance_to(goal) > REPATH_M:
		if layer == "public" and _public_plans_left <= 0 and not _is_short(pos, goal):
			return pos   # civilians queue for a route; a few ticks' pause at the door
		plan = _plan(pos, goal, layer, lane_of(mover_id))
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

## True once a mover has walked their whole route to `goal` (it may stop short
## of the goal itself when the goal is off the mesh).
func finished(mover_id: StringName, goal: Vector2) -> bool:
	var plan: Dictionary = _plans.get(mover_id, {})
	return not plan.is_empty() and plan["i"] >= plan["pts"].size() and plan["goal"].distance_to(goal) <= REPATH_M

const SHOP_OPEN_HOUR := 7.0      # MR6: shop lots are public ground while businesses are open
const SHOP_CLOSE_HOUR := 22.0
const CLOSED_LOT_COST := 20.0   # after hours civilians keep off them unless there is no other way

## Called once per sim tick: refills the civilians' route-planning ration and
## opens or closes the shop lots with the clock.
func new_tick(tick: int = -1) -> void:
	_ticks += 1
	if tick >= 0 and navs.has("public"):
		var hour := SimClock.day_fraction(tick) * 24.0
		var cost := 1.0 if hour >= SHOP_OPEN_HOUR and hour < SHOP_CLOSE_HOUR else CLOSED_LOT_COST
		if navs["public"].lot_cost != cost:
			navs["public"].lot_cost = cost
	if _ticks % PUBLIC_PLAN_EVERY_TICKS == 0:
		_public_plans_left = PUBLIC_PLANS_PER_TICK

func _is_short(pos: Vector2, goal: Vector2) -> bool:
	return pos.distance_to(goal) <= SHORT_M and collision.line_clear(pos, goal, LINE_RADIUS_M)

## Player movement: slide along walls instead of walking through them.
func slide(from: Vector2, delta: Vector2) -> Vector2:
	return collision.slide(from, delta)

var _public_plans_left := PUBLIC_PLANS_PER_TICK
var _ticks := 0
var slowest_plan_usec := 0
var slowest_plan_what := ""
var plans_made := 0    # perf counters (verify_sim_perf): routes planned, and how many needed the navmesh
var plans_routed := 0

## A route for one mover. Short hops with nothing in the way are a straight
## line and never touch the navmesh: someone drifting around a doorway, or
## stepping from their door to the sidewalk, does not need a 2 ms path query.
func _plan(pos: Vector2, goal: Vector2, layer: String, lane: float = 0.0) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var plan := _plan_route(pos, goal, layer, lane)
	var took := Time.get_ticks_usec() - t0
	if took > slowest_plan_usec:
		slowest_plan_usec = took
		slowest_plan_what = "%s %d m, %d points, fallback %s" % [layer, int(pos.distance_to(goal)), plan["pts"].size(), plan.get("fallback", false)]
	return plan

func _plan_route(pos: Vector2, goal: Vector2, layer: String, lane: float) -> Dictionary:
	plans_made += 1
	if pos.distance_to(goal) <= SHORT_M and collision.line_clear(pos, goal, LINE_RADIUS_M):
		return {"goal": goal, "layer": layer, "pts": PackedVector2Array([goal]), "i": 0}
	plans_routed += 1
	if layer == "public":
		_public_plans_left -= 1
	var nav: CityNav = navs[layer]
	var start := nav.closest(pos)
	var end := nav.closest(goal)
	var pts := _keep_right(nav.path(start, end), lane)
	# Godot returns a route to the nearest reachable point when the goal cannot be
	# reached on this layer; joining that to the goal would be a straight line
	# through whatever stands between. Treat it as no route and use any walkable way.
	if pts.is_empty() or pts[pts.size() - 1].distance_to(end) > UNREACHED_M:
		pts = navs["full"].path(pos, goal)
	elif layer != "full":
		# Getting on/off public ground crosses the mover's own yard: those hops go
		# around houses (full mesh) unless the straight line is already clear.
		var head := _hop(pos, start)
		if end.distance_to(goal) <= LAST_HOP_M:
			pts.append_array(_hop(end, goal))
		head.append_array(pts)
		pts = head
	if pts.is_empty():
		pts = PackedVector2Array([goal])     # nowhere on any mesh: straight line
	return {"goal": goal, "layer": layer, "pts": pts, "i": 0}

## Everyone's shortest route is the same line hugging the same corners. Each
## walker keeps their own distance to the right of it, so a street of people is
## not a single file. The shift stays inside the clearance the navmesh already
## keeps from walls (MAX_LANE_M < agent radius), so nobody is pushed into one.
func _keep_right(pts: PackedVector2Array, lane: float) -> PackedVector2Array:
	if lane < 0.03 or pts.size() < 3:
		return pts
	var out := pts.duplicate()
	for i in range(1, pts.size() - 1):
		var along := (pts[i + 1] - pts[i - 1]).normalized()
		var q := pts[i] + Vector2(-along.y, along.x) * lane   # no snap back to the mesh: that lookup costs ~1 ms a point
		if not collision.blocked(q, 0.0):   # a corner hugging a wall keeps the shortest line there
			out[i] = q
	return out

## This walker's own distance right of the shortest line, 0 .. MAX_LANE_M.
static func lane_of(mover_id: StringName) -> float:
	return float(absi(hash([mover_id, 31])) % 1000) / 1000.0 * MAX_LANE_M

func _hop(from: Vector2, to: Vector2) -> PackedVector2Array:
	if collision.line_clear(from, to, LINE_RADIUS_M):
		return PackedVector2Array([to])
	return navs["full"].path(from, to)
