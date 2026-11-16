## TP1: first-day tips. A short tip pops up the first time something happens
## (a fixer close by, getting hungry, a cop watching, the first evening...).
## Each tip shows once per life; tips_seen is saved and the pause menu turns
## them off. Checked once a real second; one tip at a time, GAP_S apart.
class_name TipSystem
extends SystemBase

const GAP_S := 12.0          # real seconds between two tips
const START_S := 3.0         # the welcome tip waits this long into the game
const FIXER_M := 12.0
const NEED := 0.35           # a need this low earns its tip (well before NextStep.URGENT)
const EVENING_H := 19.0
## id -> the tip. The order is the priority when two apply at once.
const TIPS := {
	"start": "You're a Street rat with $40 to your name. The line at the top always says what to do next. Esc > Controls lists every key.",
	"bleeding": "You're bleeding and losing health. Press H and bandage the wound.",
	"cop": "A cop can see you. A crime in front of cops or witnesses builds a case against you: wait until nobody's looking.",
	"fixer": "That's a fixer (purple jacket). Press E next to them and pick \"Ask for work\".",
	"hungry": "You're getting hungry. Buy food at a shop counter (E), then eat it from your bag (I).",
	"thirsty": "You're getting thirsty. Buy a drink at a shop counter (E), then drink it from your bag (I).",
	"tired": "You're getting tired. Press Z to sleep: a bed at home is safest.",
	"evening": "Evening. Shops close between 8 and 11 pm and most people go home: fewer witnesses, but cops still patrol.",
	"job": "You're on a job. The top line shows where to go and how long you have. Miss the deadline and the fixers trust you less.",
}

var _last := -1000000
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % SimClock.TICKS_PER_SECOND != 0:
		return
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if not state.tips_on or me.is_down or state.sleeping or tick - _last < int(GAP_S * SimClock.TICKS_PER_SECOND):
			continue
		for id in TIPS:
			if not state.tips_seen.has(id) and applies(_world, id, me, state, tick):
				state.tips_seen.append(id)
				state.tip_text = TIPS[id]
				state.tip_serial += 1
				_last = tick
				break

static func applies(world: World, id: String, me: NPCData, state: PlayerStateData, tick: int) -> bool:
	match id:
		"start":
			return tick >= int(START_S * SimClock.TICKS_PER_SECOND)
		"bleeding":
			return me.bleeding
		"cop":
			return _cop_sees(world, me.position)
		"fixer":
			var f := NextStep.nearest_fixer(world, me.position)
			return f != null and f.position.distance_to(me.position) < FIXER_M
		"hungry":
			return me.hunger < NEED
		"thirsty":
			return me.thirst < NEED
		"tired":
			return me.fatigue < NEED
		"evening":
			return SimClock.day_fraction(tick) * 24.0 >= EVENING_H
		"job":
			return not state.job.is_empty()
	return false

static func _cop_sees(world: World, at: Vector2) -> bool:
	for id in world.spatial_index.query_nearby(at):
		var e: Entity = world.entities.get(id)
		var npc: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if npc != null and npc.is_cop and not npc.is_down and CrimeSystem.can_see(world, npc.position, at):
			return true
	return false
