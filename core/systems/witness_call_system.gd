## Witness reactions (W2). A civilian who recognised you does not report it by
## telepathy: they run for home and phone it in CALL_MIN_S..CALL_MAX_S later.
## If by then they are down (knocked out, dead), the call never happens --
## the one way to stop a report once someone has seen you.
class_name WitnessCallSystem
extends SystemBase

const CALL_MIN_S := 6.0
const CALL_MAX_S := 15.0

var silenced := 0            # calls that never happened (checks, stats)
var _calls: Array = []       # [due tick, witness NPCData, payload]
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func queue(witness: NPCData, payload: Dictionary) -> void:
	var delay := _world.runtime_rng.randf_range(CALL_MIN_S, CALL_MAX_S)
	_calls.append([_world.tick + int(delay * SimClock.TICKS_PER_SECOND), witness, payload])
	var schedule := _world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if schedule != null:
		schedule.flee(witness)
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null:
		StreetTalk.say_key(_world, player.get_component(ComponentNames.PLAYER_STATE), "witness_running")

var ignored := 0   # E4: calls nobody answered (thin police)

func pending() -> int:
	return _calls.size()

func process_entities(_entities: Dictionary, _delta: float, tick: int) -> void:
	var i := _calls.size() - 1
	while i >= 0:
		var call: Array = _calls[i]
		if tick >= call[0]:
			_calls.remove_at(i)
			_place(call[1], call[2], true)
		i -= 1

## D1: a witness who was scared or paid off puts the phone down.
func cancel(witness_id: StringName) -> void:
	var i := _calls.size() - 1
	while i >= 0:
		if _calls[i][1].id == witness_id:
			_calls.remove_at(i)
			silenced += 1
		i -= 1

## Every pending call goes through now (checks that do not want to wait).
func flush() -> void:
	for call in _calls:
		_place(call[1], call[2])
	_calls.clear()

## E4: on a block whose police are thinly funded a call can go nowhere (no car
## free, nobody picks up): from never on a fully funded block to 6 in 10 on a broke one.
func _place(witness: NPCData, payload: Dictionary, may_drop: bool = false) -> void:
	if witness.is_down:
		silenced += 1
		return
	if may_drop and payload.has("position") and BlockEconomyData.of(_world) != null:
		var police := float(BlockEconomyData.block_at(_world, payload["position"])["police"])
		if _world.runtime_rng.randf() < (1.0 - police) * 0.6:
			ignored += 1
			return
	payload["tick"] = _world.tick
	_world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, payload)
