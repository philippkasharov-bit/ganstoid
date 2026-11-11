## Combat C6: people who fight back.
##   - Gang members: hurt one and every member of that gang within GANG_CALL_M
##     comes for you for HOSTILE_S: they close in and fire from the hip.
##   - Cops: CopAISystem asks fire_at_player() while responding; they shoot only
##     at an armed threat (gun raised or fired in the last few seconds) and
##     otherwise go for the arrest.
## While hostile a person is is_busy, so the street sim leaves them alone; once
## it is over they go back to their day.
class_name NPCCombatSystem
extends SystemBase

const GANG_CALL_M := 80.0
const HOSTILE_S := 120.0
const FIRE_RANGE_M := 18.0
const FIRE_EVERY_S := 0.9
const HOLD_M := 8.0                 # close to this, then stand and shoot
const CHASE_SPEED := SimUnits.JOG

var hostile: Dictionary = {}        # npc id -> tick their fight ends
var shots_fired := 0                # checks
var _ready_at: Dictionary = {}      # npc id -> tick of their next shot
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	if hostile.is_empty():
		return
	for player in entities.values():
		var me: NPCData = player.get_component(ComponentNames.NPC)
		for id in hostile.keys():
			var npc := _npc(id)
			if npc == null or npc.is_down or me.is_down or tick >= hostile[id]:
				_calm(id)
			else:
				_fight(npc, me, delta, tick)

## The victim's gang turns on the player.
func on_assaulted(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.ASSAULTED:
		return
	var victim := _npc(payload["victim_id"])
	if victim == null or victim.gang_id == &"":
		return
	var until: int = payload["tick"] + int(HOSTILE_S * SimClock.TICKS_PER_SECOND)
	for id in _world.spatial_index.query_nearby(payload["position"]):
		var npc := _npc(id)
		if npc != null and npc.gang_id == victim.gang_id and not npc.is_down and not npc.is_crew \
				and npc.position.distance_to(payload["position"]) <= GANG_CALL_M:
			hostile[id] = until
			npc.is_busy = true
			if npc.indoors:
				npc.indoors = false
				_world.reindex_position(id)

## RG1: a gang sends `n` of its people (standing, not already fighting) after
## the player. Returns how many went.
func send_squad(gang_id: StringName, n: int, tick: int) -> int:
	var gang_e: Entity = _world.entities.get(gang_id)
	if gang_e == null:
		return 0
	var until := tick + int(HOSTILE_S * SimClock.TICKS_PER_SECOND)
	var sent := 0
	for m in gang_e.get_component(ComponentNames.GANG).member_npc_ids:
		var npc := _npc(m)
		if sent >= n or npc == null or npc.is_down or hostile.has(m):
			continue
		hostile[m] = until
		npc.is_busy = true
		if npc.indoors:
			npc.indoors = false
		_world.reindex_position(m)
		sent += 1
	return sent

## Close in, then shoot when in range and in sight; one round per FIRE_EVERY_S.
func _fight(npc: NPCData, target: NPCData, delta: float, tick: int) -> void:
	var d := npc.position.distance_to(target.position)
	var sight := d <= FIRE_RANGE_M and _in_sight(npc.position, target.position)
	if not sight or d > HOLD_M:
		npc.position = WanderBehavior.step_toward(npc.position, target.position, CHASE_SPEED, delta, HOLD_M * 0.5, npc.id)
		_world.reindex_position(npc.id)
	if sight:
		fire_at(npc, target.position, tick)

## One round at `target` if this shooter is ready. Returns true if a shot went off.
func fire_at(npc: NPCData, target: Vector2, tick: int) -> bool:
	if tick < _ready_at.get(npc.id, 0):
		return false
	_ready_at[npc.id] = tick + int(FIRE_EVERY_S * SimClock.TICKS_PER_SECOND)
	CombatSystem.npc_shoot(_world, npc, target, _world.runtime_rng)
	shots_fired += 1
	return true

## A cop facing an armed threat in sight and range: shoots. Returns true if the
## cop is engaging (and should not walk in for the arrest).
func cop_engages(cop: NPCData, player: NPCData, state: PlayerStateData, tick: int) -> bool:
	if not CombatSystem.is_armed_threat(state, tick):
		return false
	var d := cop.position.distance_to(player.position)
	if d > FIRE_RANGE_M or not _in_sight(cop.position, player.position):
		return false
	fire_at(cop, player.position, tick)
	return d <= HOLD_M   # further out they keep closing while firing

func _calm(id: StringName) -> void:
	hostile.erase(id)
	_ready_at.erase(id)
	var npc := _npc(id)
	if npc != null:
		npc.is_busy = false

func _in_sight(a: Vector2, b: Vector2) -> bool:
	return SimNav.active == null or SimNav.active.collision.line_clear(a, b, 0.0)

func _npc(id: StringName) -> NPCData:
	var entity: Entity = _world.entities.get(id)
	return null if entity == null else entity.get_component(ComponentNames.NPC)
