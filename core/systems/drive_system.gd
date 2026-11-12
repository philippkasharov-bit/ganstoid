## Commuting by car (V4). Some people own a car (CarOwnership at new game: a
## car parked near home). When they set off on a long trip and their car is
## close, they drive: the real streets, the right-hand lane, one-way streets
## respected, stopping for lights, stop signs and whatever is in front. At the
## other end they park at the kerb near the door and walk in. The car stays
## where they left it, so tomorrow it starts from there.
## These are the only cars on the move: nobody drives around for nothing.
class_name DriveSystem
extends SystemBase

const MIN_TRIP_M := 450.0       # shorter than this they walk
const CAR_NEAR_M := 90.0        # the car has to be this close to get in
const SPEED := 11.0
const PARK_RIGHT_M := 2.2
const PLANS_PER_TICK := 1
const OWNER_SHARE := 0.55       # LA: most households have a car
const OWN_NEAR_M := 150.0

static var graph: RoadGraph     # set by WorldDriver
var drives := {}                # npc id -> {car, pts, i, door}
var trips_driven := 0
var _plans_left := 0
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

## New game: people with a job get the car parked nearest their home (if one is close).
static func assign_owners(world: World, rng: RandomNumberGenerator) -> int:
	var cars: Array = []
	for e in world.get_entities_with_component(ComponentNames.VEHICLE).values():
		cars.append(e.get_component(ComponentNames.VEHICLE))
	var owners := 0
	var people: Array = world.get_entities_with_component(ComponentNames.NPC).values()
	people.sort_custom(func(a: Entity, b: Entity) -> bool: return String(a.id) < String(b.id))
	for e in people:
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.is_cop or n.work_building_id == &"" or not world.entities.has(n.home_building_id) or e.has_component(ComponentNames.PLAYER_STATE):
			continue
		if rng.randf() > OWNER_SHARE:
			continue
		var home: Vector2 = world.entities[n.home_building_id].get_component(ComponentNames.BUILDING).position
		var best: VehicleData = null
		var best_d := OWN_NEAR_M
		for c in cars:
			if c.owner_id == &"street" and c.position.distance_to(home) < best_d:
				best = c
				best_d = c.position.distance_to(home)
		if best != null:
			best.owner_id = n.id
			best.locked = true
			n.car_id = best.id
			owners += 1
	return owners

## Called instead of walking: true if this person drives to `door`.
func try_drive(npc: NPCData, door: Vector2) -> bool:
	if graph == null or npc.car_id == &"" or npc.position.distance_to(door) < MIN_TRIP_M or _plans_left <= 0:
		return false
	var car_e: Entity = _world.entities.get(npc.car_id)
	if car_e == null:
		return false
	var car: VehicleData = car_e.get_component(ComponentNames.VEHICLE)
	if car.driver_id != &"" or car.damage >= VehicleSystem.WRECKED or car.position.distance_to(npc.position) > CAR_NEAR_M:
		return false   # stolen, wrecked, or left across town
	_plans_left -= 1
	var pts := graph.route(car.position, door)
	if pts.size() < 2:
		return false
	car.driver_id = npc.id
	car.touched = true
	npc.indoors = true   # in the car: not on the pavement
	_world.spatial_index.remove(npc.id)
	var schedule := _world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if schedule != null:
		schedule.street.put_inside(npc, npc.position)
	drives[npc.id] = {"car": car, "pts": pts, "i": 0, "door": door, "npc": npc}
	trips_driven += 1
	return true

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	_plans_left = PLANS_PER_TICK
	var traffic := _world.find_system(TrafficSystem) as TrafficSystem
	var me: NPCData = null
	for p in entities.values():
		me = p.get_component(ComponentNames.NPC)
	for id in drives.keys():
		_step(id, drives[id], traffic, me, delta)

func _step(id: StringName, d: Dictionary, traffic: TrafficSystem, me: NPCData, delta: float) -> void:
	var car: VehicleData = d["car"]
	if car.driver_id != id:   # carjacked: they are out on the street
		_arrive(id, d, false)
		return
	var pts: PackedVector2Array = d["pts"]
	var stop := traffic != null and me != null and (traffic._something_ahead(car, me) or traffic._must_stop(car.id, car))
	car.speed = move_toward(car.speed, 0.0 if stop else SPEED, (9.0 if stop else 3.0) * delta)
	var step := car.speed * delta
	while step > 0.0 and d["i"] < pts.size():
		var target: Vector2 = pts[d["i"]]
		var to := target - car.position
		if to.length() <= step:
			car.position = target
			step -= to.length()
			d["i"] += 1
		else:
			car.heading = lerp_angle(car.heading, to.angle(), minf(1.0, delta * 6.0))
			car.position += to.normalized() * step
			step = 0.0
	_world.reindex_position(car.id)
	if d["i"] >= pts.size():
		_arrive(id, d, true)

func _arrive(id: StringName, d: Dictionary, parked: bool) -> void:
	drives.erase(id)
	var car: VehicleData = d["car"]
	var npc: NPCData = d["npc"]
	if parked:
		car.position += Vector2.from_angle(car.heading).orthogonal() * PARK_RIGHT_M   # pull in to the kerb
		car.speed = 0.0
		car.driver_id = &""
		_world.reindex_position(car.id)
	npc.position = car.position
	npc.indoors = false
	_world.reindex_position(npc.id)
	var schedule := _world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if schedule != null:
		schedule.street.start_trip(npc, [], d["door"], 0.0)   # the last bit on foot

## After a jump in time (sleep, prison): everyone gets out where they are.
func clear() -> void:
	for id in drives.keys():
		var d: Dictionary = drives[id]
		d["car"].driver_id = &""
		d["car"].speed = 0.0
		d["npc"].indoors = false
	drives.clear()
