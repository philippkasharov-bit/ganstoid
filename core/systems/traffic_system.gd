## Traffic and police pursuits (V2).
##   Traffic: up to CARS cars drive the streets around the player, in the
##   right-hand lane, at a city speed; at a street's end they turn onto a
##   connecting one. They stop for whatever is in front (a person, a car, you).
##   Cars too far away are moved to a street near you (nobody sees it happen).
##   They are real cars: E next to one stopped to pull the driver out (carjack).
##   Pursuit: wanted (warrant, or cops already on you) and driving, a patrol
##   car follows the exact way you drove. Get far enough ahead for long enough
##   and they lose you; stop with them on your bumper and you are arrested.
class_name TrafficSystem
extends SystemBase

const CARS := 0                    # V4: no cars driving around for nothing; people drive their own (DriveSystem)
static var CARS_OVERRIDE := 0      # checks only
const NEAR_M := 450.0
const SPAWN_MIN_M := 150.0
const SPEED := 11.0
const SPEED_ART := 14.0
const GAP_M := 7.0
const TIERS := ["res", "art"]
const JOIN_M := 4.0
const CRUMB_EVERY := 15            # ticks between breadcrumbs of your drive
const CHASE_SPEED := 18.0
const LOSE_M := 220.0
const LOSE_S := 15.0
const CATCH_M := 7.0
const DRIVER := &"traffic"
const COP_DRIVER := &"cop_car"

static var roads: Array = []        # set by WorldDriver (the city's streets)
static var junctions: Junctions     # MP3a: signals and stop signs (set by WorldDriver)
const STOP_LINE_M := 14.0           # a red light or stop sign this far ahead: stop
const STOP_SIGN_WAIT_S := 1.5
var _ends := {}                     # quantised end point -> [[road index, from_start]]
var _drive := {}                    # car id -> [road index, point index, dir (+1/-1)]
var _crumbs := PackedVector2Array()
var _chaser: StringName = &""
var _far_ticks := 0
var _spawned := 0
var _nearby: Array[int] = []
var _blocks: Array[StringName] = []
var _block_tick := -1000000
const BLOCK_EVERY_S := 30.0
const BLOCK_AHEAD_M := 140.0
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	if roads.is_empty():
		return
	if _ends.is_empty():
		_index()
	for p in entities.values():
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if tick % 30 == 0:
			_keep_near(me.position)
		for id in _drive.keys():
			_step(id, me, delta)
		_pursuit(me, state, delta, tick)

func _index() -> void:
	for i in roads.size():
		if not TIERS.has(roads[i]["tier"]):
			continue
		var pts: PackedVector2Array = roads[i]["pts"]
		for at_start in [true, false]:
			var key := _key(pts[0] if at_start else pts[pts.size() - 1])
			if not _ends.has(key):
				_ends[key] = []
			_ends[key].append([i, at_start])

static func _key(p: Vector2) -> Vector2i:
	return Vector2i((p / JOIN_M).round())

## Cars too far from the player re-appear on a street nearer them.
func _keep_near(at: Vector2) -> void:
	var rng := _world.runtime_rng
	_nearby.clear()
	for i in roads.size():   # streets around you (cheap: ~5k roads, every half second)
		if TIERS.has(roads[i]["tier"]) and roads[i]["pts"][0].distance_squared_to(at) < (NEAR_M + 200.0) * (NEAR_M + 200.0):
			_nearby.append(i)
	if _nearby.is_empty():
		return
	for id in _drive.keys():
		var car: VehicleData = _car(id)
		if car == null or car.driver_id != DRIVER:
			_drive.erase(id)
		elif car.position.distance_to(at) > NEAR_M:
			_place(car, at, rng)
	var tries := 0
	while _drive.size() < maxi(CARS, CARS_OVERRIDE) and tries < 20:
		tries += 1
		var car := VehicleData.new()
		car.id = StringName("traffic_%d" % _spawned)
		_spawned += 1
		car.color = VehicleSeeder.COLORS[rng.randi() % VehicleSeeder.COLORS.size()]
		car.driver_id = DRIVER
		car.touched = true
		car.locked = true
		if _place(car, at, rng):
			var e := Entity.new(car.id)
			e.add_component(car)
			_world.register_entity(e)

func _place(car: VehicleData, at: Vector2, rng: RandomNumberGenerator) -> bool:
	for attempt in 12:
		var i: int = _nearby[rng.randi() % _nearby.size()]
		var road: Dictionary = roads[i]
		if not TIERS.has(road["tier"]):
			continue
		var pts: PackedVector2Array = road["pts"]
		var k := rng.randi() % pts.size()
		var d := pts[k].distance_to(at)
		if d < SPAWN_MIN_M or d > NEAR_M * 0.9:
			continue
		var dir := 1 if rng.randf() < 0.5 else -1
		var next := clampi(k + dir, 0, pts.size() - 1)
		if next == k:
			dir = -dir
			next = clampi(k + dir, 0, pts.size() - 1)
		car.position = _lane(pts[k], pts[next], road)
		car.heading = (pts[next] - pts[k]).angle()
		car.speed = 0.0
		_drive[car.id] = [i, next, dir]
		if _world.entities.has(car.id):
			_world.reindex_position(car.id)
		return true
	return false

## The right-hand lane: a quarter of the roadway right of the centre line.
static func _lane(a: Vector2, b: Vector2, road: Dictionary) -> Vector2:
	var dir := (b - a).normalized()
	return a + Vector2(-dir.y, dir.x) * float(road.get("w", 8.0)) * 0.25

func _step(id: StringName, me: NPCData, delta: float) -> void:
	var car := _car(id)
	if car == null:
		_drive.erase(id)
		return
	var d: Array = _drive[id]
	var road: Dictionary = roads[d[0]]
	var pts: PackedVector2Array = road["pts"]
	var prev_i: int = d[1] - d[2]
	var prev: Vector2 = pts[prev_i] if prev_i >= 0 and prev_i < pts.size() else car.position
	var along := (pts[d[1]] - prev).normalized()
	var target: Vector2 = pts[d[1]] + Vector2(-along.y, along.x) * float(road.get("w", 8.0)) * 0.25   # right-hand lane
	var cruise := SPEED_ART if road["tier"] == "art" else SPEED
	var blocked := _something_ahead(car, me) or _must_stop(id, car)
	car.speed = move_toward(car.speed, 0.0 if blocked else cruise, (9.0 if blocked else 3.0) * delta)
	var to := target - car.position
	var step := car.speed * delta
	if to.length() <= maxf(step, 1.0):
		_advance(id, d, pts)
	if to.length() > 0.01:
		car.heading = lerp_angle(car.heading, to.angle(), minf(1.0, delta * 4.0))
		car.position += Vector2.from_angle(car.heading) * minf(step, to.length())
		_world.reindex_position(id)

func _advance(id: StringName, d: Array, pts: PackedVector2Array) -> void:
	var nxt: int = d[1] + d[2]
	if nxt >= 0 and nxt < pts.size():
		d[1] = nxt
		return
	var options: Array = _ends.get(_key(pts[d[1]]), []).filter(func(o: Array) -> bool: return o[0] != d[0])
	if options.is_empty():
		d[2] = -d[2]   # dead end: turn round
		d[1] = clampi(d[1] + d[2], 0, pts.size() - 1)
		return
	var pick: Array = options[_world.runtime_rng.randi() % options.size()]
	var road_pts: PackedVector2Array = roads[pick[0]]["pts"]
	d[0] = pick[0]
	d[2] = 1 if pick[1] else -1
	d[1] = clampi(1 if pick[1] else road_pts.size() - 2, 0, road_pts.size() - 1)

var _stopped_at := {}   # car id -> tick it came to a stop sign

## MP3a: a red or amber light ahead, or a stop sign not yet waited at.
func _must_stop(id: StringName, car: VehicleData) -> bool:
	if junctions == null:
		return false
	var fwd := Vector2.from_angle(car.heading)
	for j in junctions.near(car.position + fwd * STOP_LINE_M * 0.5, STOP_LINE_M):
		var rel: Vector2 = j["c"] - car.position
		var ahead := rel.dot(fwd)
		if ahead < 5.0 or ahead > STOP_LINE_M or absf(fwd.cross(rel)) > 6.0:
			continue
		if j["kind"] == "signal":
			return Junctions.light(j, fwd, float(_world.tick) / SimClock.TICKS_PER_SECOND) != "green"
		var since: int = _stopped_at.get(id, -1)
		if since < 0:
			if car.speed < 0.5:
				_stopped_at[id] = _world.tick
			return true
		if _world.tick - since < int(STOP_SIGN_WAIT_S * SimClock.TICKS_PER_SECOND):
			return true
		return false
	_stopped_at.erase(id)
	return false

## A person, a moving car or you in the lane just ahead (parked cars sit
## at the kerb, outside the lane, and are ignored).
func _something_ahead(car: VehicleData, me: NPCData) -> bool:
	var fwd := Vector2.from_angle(car.heading)
	for id in _world.spatial_index.query_nearby(car.position):
		if id == car.id:
			continue
		var e: Entity = _world.entities.get(id)
		if e == null:
			continue
		var p: Variant = null
		var other: VehicleData = e.get_component(ComponentNames.VEHICLE)
		if other != null:
			if other.driver_id == &"" and not other.touched:
				continue
			p = other.position
		else:
			var n: NPCData = e.get_component(ComponentNames.NPC)
			if n != null and not n.indoors and not n.is_down:
				p = n.position
		if p == null:
			continue
		var rel: Vector2 = p - car.position
		var ahead := rel.dot(fwd)
		if ahead > 0.0 and ahead < car.length_m * 0.5 + GAP_M and absf(fwd.cross(rel)) < 1.6:
			return true
	return false

## E next to a stopped traffic car: the driver is pulled out and the car is yours.
static func carjack(world: World, me: NPCData, state: PlayerStateData, car: VehicleData) -> Dictionary:
	if car.speed > 2.0:
		return {"ok": false, "reason": "too_fast"}
	car.driver_id = &""
	car.locked = false
	car.speed = 0.0
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.ARMED_ROBBERY])
	Traits.deed(world, state, &"cars")
	return VehicleSystem.use_door(world, me, state)

## The nearest traffic car within reach, or null.
static func traffic_car_near(world: World, at: Vector2) -> VehicleData:
	for id in world.spatial_index.query_nearby(at):
		var e: Entity = world.entities.get(id)
		var c: VehicleData = e.get_component(ComponentNames.VEHICLE) if e != null else null
		if c != null and c.driver_id != &"" and c.driver_id != COP_DRIVER and c.driver_id != PlayerFactory.PLAYER_ENTITY_ID and c.position.distance_to(at) <= VehicleSystem.ENTER_M + 1.0:
			return c
	return null

func _pursuit(me: NPCData, state: PlayerStateData, delta: float, tick: int) -> void:
	var wanted := state.case_evidence >= CaseSystem.WARRANT_AT or state.law_tier != GanstoidEnums.LawTier.CLEAN
	if state.vehicle_id == &"" or not wanted:
		if _chaser != &"" and not wanted:
			_end_chase(state, "")
		_crumbs.clear()
		return
	if tick % CRUMB_EVERY == 0:
		_crumbs.append(me.position)
	if _chaser == &"":
		if _crumbs.size() < 4:
			return
		_start_chase(state)
		return
	var cop := _car(_chaser)
	if cop == null:
		_chaser = &""
		return
	while not _crumbs.is_empty() and cop.position.distance_to(_crumbs[0]) < 3.0:
		_crumbs.remove_at(0)
	var goal: Vector2 = _crumbs[0] if not _crumbs.is_empty() else me.position
	var to := goal - cop.position
	cop.speed = CHASE_SPEED
	cop.heading = to.angle()
	cop.position += to.normalized() * minf(CHASE_SPEED * delta, to.length())
	_world.reindex_position(_chaser)
	var gap := cop.position.distance_to(me.position)
	var mine := _car(state.vehicle_id)
	if gap <= CATCH_M and mine != null and absf(mine.speed) < 2.0:
		_end_chase(state, "caught")
		var cops := _world.find_system(CopAISystem) as CopAISystem
		if cops != null:
			cops._arrest(me, state)
		return
	if mine != null and tick - _block_tick > int(BLOCK_EVERY_S * SimClock.TICKS_PER_SECOND) and mine.speed > 8.0:
		_roadblock(mine)
		_block_tick = tick
	_far_ticks = _far_ticks + 1 if gap > LOSE_M else 0
	if _far_ticks > int(LOSE_S * SimClock.TICKS_PER_SECOND):
		_end_chase(state, "lost")

func _start_chase(state: PlayerStateData) -> void:
	var cop := VehicleData.new()
	cop.id = StringName("cop_car_%d" % _spawned)
	_spawned += 1
	cop.color = Color(0.12, 0.12, 0.14)
	cop.driver_id = COP_DRIVER
	cop.touched = true
	cop.position = _crumbs[0]
	var e := Entity.new(cop.id)
	e.add_component(cop)
	_world.register_entity(e)
	_chaser = cop.id
	_far_ticks = 0
	StreetTalk.say_key(_world, state, "chase_on")

## V3: two patrol cars parked nose to nose across the street ahead of you.
func _roadblock(mine: VehicleData) -> void:
	var fwd := Vector2.from_angle(mine.heading)
	var spot := mine.position + fwd * BLOCK_AHEAD_M
	var best := Vector2.INF
	var along := fwd
	for i in _nearby:
		var pts: PackedVector2Array = roads[i]["pts"]
		for k in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(spot, pts[k], pts[k + 1])
			if q.distance_to(spot) < best.distance_to(spot):
				best = q
				along = (pts[k + 1] - pts[k]).normalized()
	if best == Vector2.INF or best.distance_to(spot) > 40.0:
		return
	for side in [-1.0, 1.0]:
		var cop := VehicleData.new()
		cop.id = StringName("block_%d" % _spawned)
		_spawned += 1
		cop.color = Color(0.12, 0.12, 0.14)
		cop.driver_id = COP_DRIVER
		cop.touched = true
		cop.heading = along.orthogonal().angle()
		cop.position = best + along * side * 1.2 + along.orthogonal() * side * 2.0
		var e := Entity.new(cop.id)
		e.add_component(cop)
		_world.register_entity(e)
		_blocks.append(cop.id)

func _end_chase(state: PlayerStateData, how: String) -> void:
	for b in _blocks:
		if _world.entities.has(b):
			_world.unregister_entity(b)
	_blocks.clear()
	if _chaser != &"":
		_world.unregister_entity(_chaser)
	_chaser = &""
	_crumbs.clear()
	if how == "lost":
		state.law_tier = GanstoidEnums.LawTier.CLEAN
		StreetTalk.say_key(_world, state, "chase_lost")

func chasing() -> bool:
	return _chaser != &""

func _car(id: StringName) -> VehicleData:
	var e: Entity = _world.entities.get(id)
	return e.get_component(ComponentNames.VEHICLE) if e != null else null
