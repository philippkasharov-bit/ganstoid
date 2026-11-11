## Wounds (G3). Only the hurt are looked at: CombatSystem reports each hit.
##   - Bleeding costs BLEED_PER_MIN health a real minute until a bandage (or,
##     for NPCs, the wound closing by itself after a while); at 0 you are dead.
##   - A knockout ends at ko_until_tick: up with a little health, and a
##     civilian goes back to their day (the calendar picks them up again).
class_name WoundSystem
extends SystemBase

const BLEED_PER_MIN := 0.4
const NPC_CLOT_S := 75.0            # a passer-by's wound stops bleeding on its own
const WAKE_HEALTH := 0.3

var _hurt: Dictionary = {}          # id -> tick of the hit
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE   # entities unused: the hurt list drives it

func on_wounded(event_name: StringName, payload: Dictionary) -> void:
	if event_name == GanstoidEvents.WOUNDED:
		_hurt[payload["id"]] = _world.tick

func process_entities(_entities: Dictionary, delta: float, tick: int) -> void:
	for id in _hurt.keys():
		var entity: Entity = _world.entities.get(id)
		var npc: NPCData = entity.get_component(ComponentNames.NPC) if entity != null else null
		if npc == null or _settled(npc, id, delta, tick):
			_hurt.erase(id)

## One tick of one wounded person. Returns true when nothing is left to track.
func _settled(npc: NPCData, id: StringName, delta: float, tick: int) -> bool:
	if npc.ko_until_tick >= 0:
		if tick < npc.ko_until_tick:
			return false
		_wake(npc, tick)
	if npc.is_down:
		return true   # dead: nothing more happens to a body
	if npc.bleeding:
		npc.health = maxf(0.0, npc.health - BLEED_PER_MIN * delta / 60.0)
		var is_player := id == PlayerFactory.PLAYER_ENTITY_ID
		if not is_player and tick - _hurt[id] > int(NPC_CLOT_S * SimClock.TICKS_PER_SECOND):
			npc.bleeding = false
		if npc.health <= 0.0:
			npc.is_down = true
			npc.bleeding = false
			npc.is_busy = false
			return true
	return not npc.bleeding

func _wake(npc: NPCData, tick: int) -> void:
	npc.ko_until_tick = -1
	npc.is_down = false
	npc.health = maxf(npc.health, WAKE_HEALTH)
	var schedule := _world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if schedule != null and not npc.is_cop and not npc.is_crew and npc.id != PlayerFactory.PLAYER_ENTITY_ID:
		schedule.replan(npc, tick)
