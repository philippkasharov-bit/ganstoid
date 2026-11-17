## CA1: a crew with wants of its own. Each member gets a nature the first
## time this system sees them (an in-play roll):
##   loyal    rarely asks for anything; when they love you, a gift or a tip
##   greedy   wants a daily wage, then a bigger one
##   climber  wants to run their own corner: promote them (lieutenant: their
##            corner pays LIEUTENANT_BONUS more) and keep them happy, or one
##            day they walk off with another member and a slice of your cash
##   rat      when you have heat or a case and they are not loyal, someone
##            warns you they've been talking to a cop: deal with it within a
##            day or they walk and become a witness against you (CT1)
## Asks come once a game day at most per member, as a phone message and a
## card on Phone > Crew with buttons (ui_crew). An ask left alone for
## ASK_DAYS picks its own answer (the worst one). Wages are paid each
## morning from your cash; can't pay, they sour.
class_name CrewAmbitionSystem
extends SystemBase

const EVERY := 60
const PHASE := 43
const NATURES := {&"loyal": 0.35, &"greedy": 0.3, &"climber": 0.2, &"rat": 0.15}
const ASK_DAYS := 1.0
const WAGE_STEP := 30          # a greedy ask is this much more a day
const WAGE_MAX := 150
const LIEUTENANT_BONUS := 1.5
const RAT_PAY := 300
const GREED_CHANCE := 0.35     # a day, once they've been with you GREED_AFTER days
const GREED_AFTER := 2
const CLIMB_AT := 0.6          # loyalty a climber needs before asking for a corner
const CLIMB_CHANCE := 0.3
const TAKEOVER_BELOW := 0.35   # a lieutenant this sour may make a move
const TAKEOVER_CHANCE := 0.5
const TAKEOVER_SHARE := 0.15   # of your cash they leave with
const RAT_BELOW := 0.55
const RAT_CHANCE := 0.4
const GIFT_AT := 0.75
const GIFT_CHANCE := 0.15
## What each ask offers, in order: [choice, button text].
const CHOICES := {
	"raise": [["pay", "Pay $%d a day"], ["refuse", "No"], ["cut", "Cut them loose"]],
	"corner": [["promote", "Give them a corner"], ["refuse", "Not yet"], ["cut", "Cut them loose"]],
	"rat": [["pay", "Pay them to keep quiet ($%d)"], ["scare", "Scare them straight"], ["cut", "Cut them loose (they'll talk)"]],
}

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _day := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	for p in entities.values():
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if not state.ui_crew.is_empty():
			answer(_world, me, state, state.ui_crew.get("id", &""), String(state.ui_crew.get("choice", "")))
			state.ui_crew = {}
		var day := HustleSystem.day_of(tick)
		if day == _day:
			continue
		var first := _day == -1
		_day = day
		if first:
			continue
		new_day(_world, me, state, tick)

## Once a game day: wages, asks left too long, and new asks.
static func new_day(world: World, me: NPCData, state: PlayerStateData, tick: int) -> void:
	var rng := world.runtime_rng
	for id in state.crew_wages.keys():
		var n := _crew(world, state, id)
		if n == null:
			state.crew_wages.erase(id)
			continue
		var wage := int(state.crew_wages[id])
		if me.cash >= wage:
			Wallet.spend(world, wage)
			n.loyalty = minf(1.0, n.loyalty + 0.03)
		else:
			n.loyalty = maxf(0.0, n.loyalty - 0.15)
			PhoneSystem.push(world, state, _name(n), "Where's my money?")
	for ask in state.crew_asks.duplicate():
		if tick >= int(ask.get("until", 0)):
			answer(world, me, state, ask["id"], "cut" if ask["kind"] == "rat" else "refuse")
	for id in state.crew_ids.duplicate():
		var n := _crew(world, state, id)
		if n == null or _asked(state, id):
			continue
		if n.ambition == &"":
			n.ambition = _roll_nature(rng)
		n.crew_days += 1
		var case := state.case_evidence > 0.0 or not state.trial.is_empty() or state.law_tier != GanstoidEnums.LawTier.CLEAN
		match n.ambition:
			&"greedy":
				if n.crew_days >= GREED_AFTER and int(state.crew_wages.get(id, 0)) < WAGE_MAX and rng.randf() < GREED_CHANCE:
					_ask(world, state, n, "raise", int(state.crew_wages.get(id, 0)) + WAGE_STEP, "I'm worth more than this. $%d a day, or I walk.")
			&"climber":
				if n.crew_rank == 0 and n.loyalty >= CLIMB_AT and rng.randf() < CLIMB_CHANCE:
					_ask(world, state, n, "corner", 0, "I'm ready. Let me run my own corner.")
				elif n.crew_rank == 1 and n.loyalty < TAKEOVER_BELOW and rng.randf() < TAKEOVER_CHANCE:
					takeover(world, me, state, n)
			&"rat":
				if case and n.loyalty < RAT_BELOW and rng.randf() < RAT_CHANCE:
					_ask(world, state, n, "rat", RAT_PAY, "")
					PhoneSystem.push(world, state, "Word on the street", "Saw %s talking to a cop on the corner. Thought you should know." % _name(n))
			_:
				if n.loyalty >= GIFT_AT and rng.randf() < GIFT_CHANCE:
					var gift := rng.randi_range(50, 150)
					Wallet.earn_dirty(world, gift)
					PhoneSystem.push(world, state, _name(n), "Found some extra. $%d, it's yours. We good." % gift)

## You answer an ask (from the phone, or the system when time runs out).
static func answer(world: World, me: NPCData, state: PlayerStateData, id: StringName, choice: String) -> String:
	var ask := {}
	for a in state.crew_asks:
		if a["id"] == id:
			ask = a
	var n := _crew(world, state, id)
	if ask.is_empty() or n == null:
		return ""
	state.crew_asks.erase(ask)
	var kind: String = ask["kind"]
	match [kind, choice]:
		["raise", "pay"]:
			state.crew_wages[id] = int(ask["amount"])
			n.loyalty = minf(1.0, n.loyalty + 0.2)
		["corner", "promote"]:
			n.crew_rank = 1
			n.loyalty = minf(1.0, n.loyalty + 0.25)
			StampView.put(state, "LIEUTENANT", "%s runs a corner now" % _name(n), UiTheme.GOOD)
		["rat", "pay"]:
			if me.cash < int(ask["amount"]):
				return answer_again(world, me, state, ask, "cut")
			Wallet.spend(world, int(ask["amount"]))
			n.loyalty = minf(1.0, n.loyalty + 0.35)
		["rat", "scare"]:
			n.fear = 1.0   # too scared to talk, in court or out (CT1)
			n.loyalty = maxf(0.0, n.loyalty - 0.1)
			MemorySystem.remember(world, state, id, "threatened")
		["rat", "cut"]:
			CrewLoyaltySystem.snitch(world, state, id)   # walks, and talks
			state.memories[id] = {"deed": "saw_crime", "feel": -0.9, "day": SimClock.day_number(world.tick), "n": 1}
			_left(world, state, n)
			StampView.put(state, "SNITCH", "%s is talking to the police" % _name(n), UiTheme.BAD)
		[_, "cut"]:
			_out(world, state, n)
			MemorySystem.remember(world, state, id, "threatened")
		[_, "refuse"]:
			n.loyalty = maxf(0.0, n.loyalty - 0.25)
			if n.loyalty < 0.15:
				_out(world, state, n)
				PhoneSystem.push(world, state, _name(n), "I'm done. Find somebody else.")
	return kind + ":" + choice

static func answer_again(world: World, me: NPCData, state: PlayerStateData, ask: Dictionary, choice: String) -> String:
	state.crew_asks.append(ask)
	return answer(world, me, state, ask["id"], choice)

## A sour lieutenant walks with another member and a slice of your cash.
static func takeover(world: World, me: NPCData, state: PlayerStateData, n: NPCData) -> void:
	var take := int(me.cash * TAKEOVER_SHARE)
	if take > 0:
		Wallet.spend(world, take)
	var with := ""
	for other in state.crew_ids:
		if other != n.id:
			var o := _crew(world, state, other)
			if o != null and o.loyalty < 0.6:
				_out(world, state, o)
				with = " and %s" % _name(o)
				break
	_out(world, state, n)
	MemorySystem.remember(world, state, n.id, "threatened")
	PhoneSystem.push(world, state, _name(n), "Your corners are mine now. Don't come round.")
	StampView.put(state, "BETRAYED", "%s%s went their own way · -$%d" % [_name(n), with, take], UiTheme.BAD)

static func _ask(world: World, state: PlayerStateData, n: NPCData, kind: String, amount: int, text: String) -> void:
	state.crew_asks.append({"id": n.id, "kind": kind, "amount": amount, "until": world.tick + int(ASK_DAYS * SimClock.day_ticks)})
	if text != "":
		PhoneSystem.push(world, state, _name(n), text % amount if text.contains("%d") else text)

static func _asked(state: PlayerStateData, id: StringName) -> bool:
	return state.crew_asks.any(func(a: Dictionary) -> bool: return a["id"] == id)

## Out of the crew (and their wage stops).
static func _out(world: World, state: PlayerStateData, n: NPCData) -> void:
	state.crew_ids.erase(n.id)
	n.is_crew = false
	n.recruit_refused = true
	n.crew_role = GanstoidEnums.CrewRole.UNASSIGNED
	_left(world, state, n)

static func _left(_world: World, state: PlayerStateData, n: NPCData) -> void:
	state.crew_wages.erase(n.id)
	n.crew_rank = 0
	state.crew_asks = state.crew_asks.filter(func(a: Dictionary) -> bool: return a["id"] != n.id)

static func _roll_nature(rng: RandomNumberGenerator) -> StringName:
	var r := rng.randf()
	for k in NATURES:
		r -= NATURES[k]
		if r < 0.0:
			return k
	return &"loyal"

static func _crew(world: World, state: PlayerStateData, id: StringName) -> NPCData:
	if not state.crew_ids.has(id):
		return null
	var e: Entity = world.entities.get(id)
	return e.get_component(ComponentNames.NPC) if e != null else null

static func _name(n: NPCData) -> String:
	return n.display_name if n.display_name != "" else "Your guy"

## The ask card's text for Phone > Crew.
static func ask_text(world: World, state: PlayerStateData, ask: Dictionary) -> String:
	var n := _crew(world, state, ask["id"])
	var who := _name(n) if n != null else "?"
	match String(ask["kind"]):
		"raise": return "%s wants $%d a day." % [who, int(ask["amount"])]
		"corner": return "%s wants to run a corner." % who
		"rat": return "%s has been seen with a cop." % who
	return who

static func choice_text(ask: Dictionary, choice: Array) -> String:
	var t: String = choice[1]
	return t % int(ask["amount"]) if t.contains("%d") else t
