## PP1: pickpocketing is a little game, not a dice roll. "Pickpocket" (E) starts
## a lift: the mark keeps walking and you stay right behind them (within
## REACH_M, behind their back) while the lift fills over LIFT_S (faster with
## theft skill and in a crowd). In front of them or beside them for NOTICE_S,
## or bumping into them (closer than BUMP_M), and they catch you: "Hey!",
## they run, people near may report it. Drop back past LOSE_M and you lose
## them. A full lift takes their cash as before (CrimeSystem).
class_name PickpocketSystem
extends SystemBase

const LIFT_S := 3.0
const REACH_M := 1.7
const BUMP_M := 0.4
const LOSE_M := 3.0
const NOTICE_S := 0.7
const CROWD_M := 6.0
const CROWD := 3            # this many people round you (yourself and the mark aside) and it's easier
const CROWD_BONUS := 1.4
const CAUGHT_SEVERITY := 0.5   # being caught at it is a smaller report than the theft itself

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

## E > Pickpocket: starts following `target`.
static func start(world: World, state: PlayerStateData, target: StringName) -> Dictionary:
	var e: Entity = world.entities.get(target)
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	if n == null or n.is_down:
		return {"ok": false, "reason": "no_victim"}
	state.lift = {"target": target, "f": 0.0, "notice": 0.0, "last": n.position, "dir": Vector2.ZERO}
	return {"ok": true, "effect": "lifting"}

func process_entities(entities: Dictionary, delta: float, _tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.lift.is_empty():
			continue
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var result := step(_world, me, state, delta)
		if not result.is_empty():
			state.lift = {}
			StreetTalk.say(_world, state, result)

## One tick of a lift: {} while it goes on, else the result.
static func step(world: World, me: NPCData, state: PlayerStateData, delta: float) -> Dictionary:
	var lift: Dictionary = state.lift
	var e: Entity = world.entities.get(lift["target"])
	var mark: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	if mark == null or mark.is_down or mark.indoors or me.is_down:
		return {"ok": false, "reason": "lift_lost"}
	var moved: Vector2 = mark.position - lift["last"]
	if moved.length() > 0.01:
		lift["dir"] = moved.normalized()   # the way they face: the way they walk
	lift["last"] = mark.position
	var d := me.position.distance_to(mark.position)
	if d > LOSE_M:
		return {"ok": false, "reason": "lift_lost"}
	if d < BUMP_M:
		return _caught(world, me, mark)
	var dir: Vector2 = lift["dir"]
	var behind := dir == Vector2.ZERO or dir.dot((me.position - mark.position).normalized()) < -0.3
	if dir == Vector2.ZERO:
		behind = false   # standing still they look round: you can't stay unseen
	if not behind:
		lift["notice"] = float(lift["notice"]) + delta
		if float(lift["notice"]) >= NOTICE_S:
			return _caught(world, me, mark)
		return {}
	lift["notice"] = maxf(0.0, float(lift["notice"]) - delta * 0.5)
	if d <= REACH_M:
		var rate := Skills.more(state, &"theft") * (CROWD_BONUS if _crowd(world, me) >= CROWD else 1.0)
		lift["f"] = float(lift["f"]) + delta / LIFT_S * rate
		if float(lift["f"]) >= 1.0:
			return CrimeSystem.commit_crime(world, GanstoidEnums.CrimeType.PICKPOCKET, mark.id)
	return {}

## They felt it: they shout and run; anyone near may report it.
static func _caught(world: World, me: NPCData, mark: NPCData) -> Dictionary:
	var schedule := world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if schedule != null:
		schedule.flee(mark)
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.PICKPOCKET] * CAUGHT_SEVERITY)
	var p: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p != null:
		StampView.put(p.get_component(ComponentNames.PLAYER_STATE), "CAUGHT!", "they felt your hand", UiTheme.BAD)   # UI3
	return {"ok": false, "reason": "lift_caught"}

static func _crowd(world: World, me: NPCData) -> int:
	var n := 0
	for id in world.spatial_index.query_nearby(me.position):
		var e: Entity = world.entities.get(id)
		var o: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if o != null and o != me and not o.indoors and not o.is_down and o.position.distance_to(me.position) <= CROWD_M:
			n += 1
	return n - 1   # the mark is not a crowd
