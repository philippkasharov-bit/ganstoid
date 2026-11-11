## Driving (V1). Arcade bicycle model in metres: W/S throttle and brake,
## A/D steer, F gets in and out. A locked car takes HOTWIRE_S of standing at
## it (a witnessable break-in); an unlocked one is yours at once.
## Hitting a wall stops you and dents the car; hitting a person hurts them by
## speed (and is a crime like any other blow).
## Pure rules: PlayerInputSystem passes the controls in.
class_name VehicleSystem
extends RefCounted

const ACCEL := 4.5            # m/s2
const BRAKE := 9.0
const DRAG := 0.6             # m/s2 rolling and air, coasting
const MAX_SPEED := 17.0       # ~60 km/h: city driving
const MAX_REVERSE := 4.0
const WHEELBASE := 2.7
const MAX_STEER := deg_to_rad(32.0)
const ENTER_M := 3.0
const HOTWIRE_S := 6.0
const HIT_MIN_SPEED := 2.5    # slower than this you nudge people, no harm
const WRECKED := 1.0

## F: get out if in a car; otherwise get in the nearest car (or start a hotwire).
static func use_door(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	if state.vehicle_id != &"":
		return _get_out(world, me, state)
	var car := nearest_car(world, me.position)
	if car == null:
		return {"ok": false, "reason": "no_car"}
	if car.damage >= WRECKED:
		return {"ok": false, "reason": "car_wrecked"}
	if car.locked and car.owner_id != PlayerFactory.PLAYER_ENTITY_ID:
		state.hotwire_id = car.id
		state.hotwire_done_tick = world.tick + int(HOTWIRE_S * Skills.less(state, &"theft") * SimClock.TICKS_PER_SECOND)
		CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.CAR_BREAK_IN])
		return {"ok": true, "effect": "hotwiring"}
	return _get_in(world, me, state, car)

## A hotwire finishes if you stayed at the car; walking off abandons it.
static func advance_hotwire(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	if state.hotwire_id == &"":
		return {}
	var car := _car(world, state.hotwire_id)
	if car == null or car.position.distance_to(me.position) > ENTER_M:
		state.hotwire_id = &""
		return {"ok": false, "reason": "hotwire_abandoned"}
	if world.tick < state.hotwire_done_tick:
		return {}
	state.hotwire_id = &""
	car.locked = false
	Skills.train(world, state, &"theft", 10.0)
	return _get_in(world, me, state, car)

static func _get_in(world: World, me: NPCData, state: PlayerStateData, car: VehicleData) -> Dictionary:
	state.vehicle_id = car.id
	car.driver_id = me.id
	car.touched = true
	me.position = car.position
	world.reindex_position(me.id)
	return {"ok": true, "effect": "car_in"}

static func _get_out(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	var car := _car(world, state.vehicle_id)
	if car == null:
		state.vehicle_id = &""
		return {"ok": false, "reason": "no_car"}
	if absf(car.speed) > 2.0:
		return {"ok": false, "reason": "too_fast"}
	var left := Vector2.from_angle(car.heading).orthogonal() * -1.0
	var spot := car.position + left * (car.width_m * 0.5 + 0.8)
	if _blocked(spot, 0.3):
		spot = car.position - left * (car.width_m * 0.5 + 0.8)   # the other door
	car.speed = 0.0
	car.driver_id = &""
	state.vehicle_id = &""
	me.position = spot
	world.reindex_position(me.id)
	return {"ok": true, "effect": "car_out"}

## One tick of driving. throttle -1..1 (S brakes, then reverses), steer -1..1.
static func drive(world: World, car: VehicleData, throttle: float, steer: float, delta: float, skill: float = 1.0) -> Dictionary:
	var out := {}
	if car.damage >= WRECKED:
		car.speed = 0.0
		return out
	if throttle > 0.0:
		car.speed = minf(MAX_SPEED * (1.0 - car.damage * 0.5), car.speed + ACCEL * skill * throttle * delta) if car.speed >= 0.0 else car.speed + BRAKE * delta
	elif throttle < 0.0:
		car.speed = car.speed - BRAKE * delta if car.speed > 0.0 else maxf(-MAX_REVERSE, car.speed - ACCEL * 0.6 * delta)
	else:
		car.speed = move_toward(car.speed, 0.0, DRAG * delta)
	if absf(car.speed) < 0.01:
		return out
	car.heading += car.speed / WHEELBASE * tan(MAX_STEER * steer) * delta
	var forward := Vector2.from_angle(car.heading)
	var next := car.position + forward * car.speed * delta
	var nose := next + forward * signf(car.speed) * car.length_m * 0.5
	if _blocked(nose, 0.0):
		car.damage = minf(WRECKED, car.damage + absf(car.speed) * 0.02)
		out["crash"] = absf(car.speed)
		car.speed = 0.0
		return out
	car.position = next
	world.reindex_position(car.id)
	var hit := _run_into(world, car, forward)
	if not hit.is_empty():
		out["hit"] = hit
	return out

## A person in front of the bumper at speed: hurt by how fast you were going.
static func _run_into(world: World, car: VehicleData, forward: Vector2) -> Dictionary:
	if absf(car.speed) < HIT_MIN_SPEED:
		return {}
	var bumper := car.position + forward * signf(car.speed) * car.length_m * 0.5
	for id in world.spatial_index.query_nearby(bumper):
		if id == car.driver_id:
			continue
		var entity: Entity = world.entities.get(id)
		var npc: NPCData = entity.get_component(ComponentNames.NPC) if entity != null else null
		if npc == null or npc.is_down or npc.indoors or npc.position.distance_to(bumper) > car.width_m * 0.5 + 0.3:
			continue
		var w := {"damage": clampf(absf(car.speed) / 14.0, 0.2, 1.2), "blunt": absf(car.speed) < 9.0}
		var result := CombatSystem._hurt(world, npc, w)
		npc.position += forward.orthogonal() * (car.width_m * 0.5 + 0.6)   # thrown aside
		world.reindex_position(npc.id)
		car.speed *= 0.6
		car.damage = minf(WRECKED, car.damage + 0.03)
		return result
	return {}

static func nearest_car(world: World, at: Vector2) -> VehicleData:
	var best: VehicleData = null
	var best_d := ENTER_M
	for id in world.spatial_index.query_nearby(at):
		var car := _car(world, id)
		if car != null and car.driver_id == &"" and car.position.distance_to(at) <= best_d:
			best = car
			best_d = car.position.distance_to(at)
	return best

static func _car(world: World, id: StringName) -> VehicleData:
	var entity: Entity = world.entities.get(id)
	return entity.get_component(ComponentNames.VEHICLE) if entity != null else null

static func _blocked(p: Vector2, r: float) -> bool:
	return SimNav.active != null and SimNav.active.collision.blocked(p, r)
