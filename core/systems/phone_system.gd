## PH1: the phone, the hub (RP-server style, as a 90s brick phone): an inbox
## of messages (rivals, hustles, the paper, fixers), and calls. The phone
## window only asks (PlayerStateData.ui_phone); this system does it on the
## next tick, so the UI never changes the world itself:
##   {"call": fixer id}   a fixer you know picks up and offers work
##   {"take": index}      take one of the offers on the screen
## Inbox.push is how anything sends you a message.
class_name PhoneSystem
extends SystemBase

const INBOX_MAX := 30
const CALL_FIXER_MIN_REP := 0.0   # any fixer you have met takes your call

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, _tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.ui_phone.is_empty():
			continue
		var ask := state.ui_phone
		state.ui_phone = {}
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if ask.has("call"):
			_call(state, me, ask["call"])
		elif ask.has("take") and int(ask["take"]) < state.job_offers.size():
			var r := JobSystem.take(_world, state, state.job_offers[int(ask["take"])])
			state.job_offers = []
			StreetTalk.say(_world, state, r)

func _call(state: PlayerStateData, me: NPCData, who: StringName) -> void:
	if state.known.get(who, "") != "fixer":
		return
	if not state.job.is_empty():
		push(_world, state, _name(who), "You're already on something. Finish it.")
		return
	state.job_offers = JobSystem.offers(_world, state, me)
	push(_world, state, _name(who), "Got %d things that need doing. Pick one." % state.job_offers.size())

func _name(id: StringName) -> String:
	var e: Entity = _world.entities.get(id)
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	return "Fixer" if n == null else "Fixer (%s)" % n.display_name

## A message on the phone: {from, text, at (tick)}. Newest last.
static func push(world: World, state: PlayerStateData, from: String, text: String) -> void:
	state.inbox.append({"from": from, "text": text, "at": world.tick})
	while state.inbox.size() > INBOX_MAX:
		state.inbox.pop_front()
