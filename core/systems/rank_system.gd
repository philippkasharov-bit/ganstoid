## Ranks (RK1): the goal spine, street rat to city boss. Once an in-game hour
## your standing is scored from what you have built; a rank once earned is
## kept (a bad week does not make you a nobody again).
##   score = money/50 + businesses*15 + grow houses*15 + crew*8
##           + blocks held*12 + skill levels*2
## Gates: dealers only sell a gun to a Hustler or above.
class_name RankSystem
extends SystemBase

const NAMES := ["Street rat", "Hustler", "Soldier", "Lieutenant", "Boss", "Kingpin", "City boss"]
const THRESHOLDS := [0, 30, 90, 200, 400, 800, 1500]
const GUN_RANK := 1

var _last_hour := -1
const PHASE_TICKS := 23
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	var hour := (tick - PHASE_TICKS) / SimClock.hours(1.0)   # PF1: not on the same tick as the other hourly jobs
	if hour == _last_hour:
		return
	_last_hour = hour
	for player in entities.values():
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		var now := rank_for(score(_world, player.get_component(ComponentNames.NPC), state))
		if now > state.rank:
			state.rank = now
			state.fame = minf(100.0, state.fame + 10.0)   # F1: a new rank gets talked about
			state.last_message = "You're a %s now. People talk about you." % NAMES[now]
			state.message_alert = true
			state.message_serial += 1

static func score(world: World, me: NPCData, state: PlayerStateData) -> int:
	var s := me.cash / 50
	s += BusinessSystem.count_owned(world) * 15 + ProductionSystem.count_grow_houses(world) * 15
	s += state.crew_ids.size() * 8
	var t := TerritorySystem.data(world)
	if t != null:
		s += TerritorySystem.cells_held(t, TerritorySystem.PLAYER) * 12
	for skill in Skills.NAMES:
		s += Skills.level(state, skill) * 2
	return s

static func rank_for(points: int) -> int:
	var r := 0
	for i in THRESHOLDS.size():
		if points >= THRESHOLDS[i]:
			r = i
	return r

static func name_of(rank: int) -> String:
	return NAMES[clampi(rank, 0, NAMES.size() - 1)]

## Points still needed for the next rank (0 at the top).
static func to_next(world: World, me: NPCData, state: PlayerStateData) -> int:
	if state.rank >= THRESHOLDS.size() - 1:
		return 0
	return maxi(0, THRESHOLDS[state.rank + 1] - score(world, me, state))
