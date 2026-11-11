## Jobs (JB1): fixers hand out contracts. Talk to one (E: "Ask for work"),
## take one of three offers, do it before the deadline, get paid. Doing them
## well raises your name with the fixers (better pay, heists unlocked).
##   debt   find the mark and lean on them (E near them)        extortion
##   car    take a given car and drop it at the chop shop       car theft
##   hit    put the mark down (knocked out pays less than dead)
##   heist  rob a given business; cased first (stood watching it CASE_S) pays half again
## The active job is one Dictionary on PlayerStateData (saved).
class_name JobSystem
extends SystemBase

const FIXERS := 3
const DEADLINE_H := 24.0
const PAY := {"debt": 120, "car": 250, "hit": 500, "heist": 300}
const HEIST_REP := 0.4               # fixers trust you with heists from here
const DROP_M := 12.0
const CASE_M := 30.0
const CASE_S := 20.0
const KO_PAY := 0.6
const REP_GAIN := 0.12
const REP_LOSS := 0.15

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

## New game: three plain civilians are quietly fixers.
static func seed(world: World, rng: RandomNumberGenerator) -> void:
	var pool: Array = []
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if not (n.is_cop or n.is_dealer or n.gang_id != &"" or e.has_component(ComponentNames.PLAYER_STATE)):
			pool.append(n)
	pool.sort_custom(func(a: NPCData, b: NPCData) -> bool: return String(a.id) < String(b.id))
	var made := 0
	while made < mini(FIXERS, pool.size()):
		var n: NPCData = pool[rng.randi() % pool.size()]
		if not n.is_fixer:
			n.is_fixer = true
			made += 1

## Three offers from this fixer (fresh each time you ask).
static func offers(world: World, state: PlayerStateData, me: NPCData) -> Array:
	var rng := world.runtime_rng
	var kinds: Array = ["debt", "car", "hit"]
	if state.fixer_rep >= HEIST_REP:
		kinds.append("heist")
	var out: Array = []
	for i in 3:
		var kind: String = kinds[rng.randi() % kinds.size()]
		var job := _make(world, kind, me.position, rng)
		if not job.is_empty():
			job["pay"] = int(PAY[kind] * (1.0 + state.fixer_rep))
			out.append(job)
	return out

static func _make(world: World, kind: String, near: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	match kind:
		"debt", "hit":
			var mark := _someone(world, near, rng)
			return {} if mark == null else {"kind": kind, "target": mark.id, "text": ("Collect a debt from" if kind == "debt" else "Put down") + " someone %d m away" % roundi(mark.position.distance_to(near))}
		"car":
			var cars := world.get_entities_with_component(ComponentNames.VEHICLE).keys()
			if cars.is_empty():
				return {}
			var car: StringName = cars[rng.randi() % cars.size()]
			var drop := near + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(250.0, 500.0)
			return {"kind": kind, "target": car, "drop": drop, "text": "Bring a marked car to the chop shop"}
		"heist":
			var shops: Array = []
			for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
				var b: BuildingData = e.get_component(ComponentNames.BUILDING)
				if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.position.distance_to(near) < 600.0 and not BusinessSystem.owned_by_player(b):
					shops.append(b)
			if shops.is_empty():
				return {}
			var shop: BuildingData = shops[rng.randi() % shops.size()]
			return {"kind": kind, "target": shop.id, "text": "Hit a store %d m away (case it first)" % roundi(shop.position.distance_to(near))}
	return {}

static func _someone(world: World, near: Vector2, rng: RandomNumberGenerator) -> NPCData:
	var pool: Array = []
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if not (n.is_cop or n.is_crew or n.is_down or n.is_fixer or e.has_component(ComponentNames.PLAYER_STATE)) and n.position.distance_to(near) < 700.0:
			pool.append(n)
	return null if pool.is_empty() else pool[rng.randi() % pool.size()]

static func take(world: World, state: PlayerStateData, job: Dictionary) -> Dictionary:
	if not state.job.is_empty():
		return {"ok": false, "reason": "job_already"}
	state.job = job.duplicate()
	state.job["deadline"] = world.tick + SimClock.hours(DEADLINE_H)
	state.job["cased"] = 0
	if job["kind"] == "heist":
		(world.entities[job["target"]].get_component(ComponentNames.BUILDING) as BuildingData).has_been_hit = false
	return {"ok": true, "effect": "job_taken"}

## E near the debt mark.
static func collect_debt(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	var mark: NPCData = world.entities[state.job["target"]].get_component(ComponentNames.NPC)
	if mark.position.distance_to(me.position) > CrimeSystem.INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.EXTORTION])
	return _finish(world, state, 1.0)

## Where the job wants you (for the marker): the mark, the car or its drop, the store.
static func target_point(world: World, state: PlayerStateData) -> Variant:
	if state.job.is_empty():
		return null
	var e: Entity = world.entities.get(state.job["target"])
	if e == null:
		return null
	if state.job["kind"] == "car":
		return state.job["drop"] if state.vehicle_id == state.job["target"] else e.get_component(ComponentNames.VEHICLE).position
	var npc: NPCData = e.get_component(ComponentNames.NPC)
	return npc.position if npc != null else e.get_component(ComponentNames.BUILDING).position

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.job.is_empty():
			continue
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if tick > state.job["deadline"]:
			state.fixer_rep = maxf(0.0, state.fixer_rep - REP_LOSS)
			state.job = {}
			StreetTalk.say_key(_world, state, "job_failed")
			continue
		var e: Entity = _world.entities.get(state.job["target"])
		if e == null:
			continue
		match state.job["kind"]:
			"car":
				var car: VehicleData = e.get_component(ComponentNames.VEHICLE)
				if car.position.distance_to(state.job["drop"]) <= DROP_M and car.speed < 1.0:
					_say(state, _finish(_world, state, 1.0))
			"hit":
				var mark: NPCData = e.get_component(ComponentNames.NPC)
				if mark.is_down:
					_say(state, _finish(_world, state, KO_PAY if mark.ko_until_tick >= 0 else 1.0))
			"heist":
				var shop: BuildingData = e.get_component(ComponentNames.BUILDING)
				if shop.has_been_hit:
					_say(state, _finish(_world, state, 1.5 if state.job["cased"] >= int(CASE_S * SimClock.TICKS_PER_SECOND) else 1.0))
				elif me.position.distance_to(shop.position) <= CASE_M:
					state.job["cased"] += 1

func _say(state: PlayerStateData, result: Dictionary) -> void:
	StreetTalk.say(_world, state, result)

static func _finish(world: World, state: PlayerStateData, share: float) -> Dictionary:
	var pay := int(state.job["pay"] * share)
	Wallet.earn_dirty(world, pay)
	state.fixer_rep = minf(1.0, state.fixer_rep + REP_GAIN)
	state.jobs_done += 1
	state.job = {}
	return {"ok": true, "effect": "job_done", "amount": pay}
