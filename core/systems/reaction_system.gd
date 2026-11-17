## RX1: people react to you, four times a second, only round the player:
##   a gun up      everyone who sees it runs; whoever is right in front of the
##                 barrel freezes, hands up (an easy mugging)
##   followed      at night, someone you stay close behind for FOLLOW_S notices
##                 and hurries off
##   a body        people who see someone lying hurt or dead run from it
##   gang corners  a gang's people on their own block warn you off once; still
##                 there WARN_S later, with a gun out or on bad terms with them,
##                 and they come for you (a customer, friend of the gang, is let be)
## Cops, crew, dealers and the down take no part.
class_name ReactionSystem
extends SystemBase

const EVERY := 15
const PHASE := 4
const STEP_S := float(EVERY) / SimClock.TICKS_PER_SECOND
const GUN_M := 14.0
const HANDS_UP_M := 5.0
const AIM_CONE := 0.85            # cos of the angle off the barrel that counts as "at them"
const HANDS_UP_TICKS := 600
const FOLLOW_M := 7.0
const FOLLOW_S := 8.0
const DARK := 0.5
const HURRY := 0.75               # of a jog
const BODY_M := 14.0
const GANG_WARN_M := 7.0
const WARN_S := 20.0
const GANG_STAY_M := 12.0
const GANG_CALL_M := 30.0
const FRIENDLY := 0.6             # standing this good (deals, gun sales, gang jobs): they let you be
const DISLIKED := 0.35            # this bad and staying is enough; in between only a gun out starts it

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _follow: Dictionary = {}      # npc id -> seconds you have stayed close behind
var _done: Dictionary = {}        # npc id -> true once they reacted (until they are out of reach)
var _warned: Dictionary = {}      # gang id -> tick of the warning
var hands_up := 0                 # counters for the checks
var ran := 0
var hurried := 0

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	var schedule := _world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if schedule == null:
		return
	for p in entities.values():
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if me.is_down or state.sleeping:
			continue
		var dark := StreetLights.darkness(SimClock.day_fraction(tick) * 24.0) >= DARK
		var t := TerritorySystem.data(_world)
		var gang_turf := t != null and not [&"", TerritorySystem.PLAYER].has(TerritorySystem.controller(t, TerritoryData.turf_of(me.position)))
		if not (state.aiming or dark or gang_turf) and (tick / EVERY) % 4 != 0:
			continue   # PF: a quiet daytime street: a body is noticed within the second
		var bodies: Array[Vector2] = []
		var near: Array[NPCData] = []
		for id in _world.spatial_index.query_nearby(me.position):
			var e: Entity = _world.entities.get(id)
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n == null or n == me or n.indoors:
				continue
			if n.is_down:
				bodies.append(n.position)
			elif not (n.is_cop or n.is_crew):
				near.append(n)
		var seen := {}
		for n in near:
			seen[n.id] = true
			if n.gang_id != &"":
				_gang(n, me, state, tick)   # a gang's corner boys hold their ground
				continue
			if n.is_dealer or _done.has(n.id):
				continue
			var d := n.position.distance_to(me.position)
			if state.aiming and state.weapon != &"fists" and d <= GUN_M and CrimeSystem.can_see(_world, n.position, me.position):
				var aim := (state.aim_point - me.position).normalized()
				if d <= HANDS_UP_M and aim.dot((n.position - me.position).normalized()) >= AIM_CONE:
					schedule.street.hold(n, tick, HANDS_UP_TICKS)   # hands up
					hands_up += 1
				else:
					schedule.flee(n)
					ran += 1
				_done[n.id] = true
				continue
			if _sees_body(n, bodies):
				schedule.flee(n)
				ran += 1
				_done[n.id] = true
				continue
			if dark and d <= FOLLOW_M and _behind(n, me):
				_follow[n.id] = float(_follow.get(n.id, 0.0)) + STEP_S
				if _follow[n.id] >= FOLLOW_S:
					schedule.street.hurry(n, SimUnits.JOG * HURRY)
					hurried += 1
					_done[n.id] = true
			else:
				_follow.erase(n.id)
		for id in _done.keys():
			if not seen.has(id):
				_done.erase(id)   # out of reach: they can react again next time
				_follow.erase(id)

func _sees_body(n: NPCData, bodies: Array[Vector2]) -> bool:
	for b in bodies:
		if b.distance_to(n.position) <= BODY_M and CrimeSystem.can_see(_world, n.position, b):
			return true
	return false

## You are behind them: the way they walk points away from you.
func _behind(n: NPCData, me: NPCData) -> bool:
	var schedule := _world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	var goal: Variant = schedule.street.goal_of(n.id)
	if goal == null:
		return false
	return ((goal as Vector2) - n.position).normalized().dot((me.position - n.position).normalized()) < -0.3

## A gang's people on their own block: a warning, then trouble.
func _gang(n: NPCData, me: NPCData, state: PlayerStateData, tick: int) -> void:
	var t := TerritorySystem.data(_world)
	if t == null or TerritorySystem.controller(t, TerritoryData.turf_of(me.position)) != n.gang_id:
		return
	var standing: float = state.gang_standing.get(n.gang_id, 0.5)
	if standing >= FRIENDLY or not state.pending_deal.is_empty() or Rep.tier(state) >= Rep.GANG_LETS_PASS:   # RP1: they know who you are
		return
	var d := n.position.distance_to(me.position)
	var combat := _world.find_system(NPCCombatSystem) as NPCCombatSystem
	if combat == null or combat.hostile.has(n.id):
		return
	if not _warned.has(n.gang_id) or tick - int(_warned[n.gang_id]) > int(WARN_S * 6.0 * SimClock.TICKS_PER_SECOND):
		if d <= GANG_WARN_M:
			_warned[n.gang_id] = tick
			StreetTalk.say_key(_world, state, "gang_warning")
		return
	var trouble := standing < DISLIKED or (state.aiming and state.weapon != &"fists")
	if trouble and tick - int(_warned[n.gang_id]) >= int(WARN_S * SimClock.TICKS_PER_SECOND) and d <= GANG_STAY_M:
		_warned[n.gang_id] = tick   # one call, then a fresh warning later
		StreetTalk.say_key(_world, state, "gang_told")
		combat.call_gang(n.gang_id, me.position, GANG_CALL_M, tick)
