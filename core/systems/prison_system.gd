## JL1: prison you live through. Inside, each prison day you choose (the
## Prison panel; ui_prison) how to spend it:
##   head_down    keep your head down: every GOOD_DAYS of it takes a day off
##   yard         work the yard: a little clean money, melee training
##   connections  make connections: when you're out, a gang likes you better
##                and a fixer has a score lined up
##   appeal       pay a lawyer (clean money) to cut APPEAL_DAYS
##   escape       try to get out: better odds with a high reputation and a
##                crew outside; fail and the sentence grows
## Outside, your crew's loyalty slips each day you're gone (less if they have
## your crib to hang out in), and the phone tells you how things stand.
class_name PrisonSystem
extends SystemBase

const PHASE := 61
const CHOICES := ["head_down", "yard", "connections", "appeal", "escape"]
const GOOD_DAYS := 3
const YARD_PAY := 40
const APPEAL_COST := 500
const APPEAL_DAYS := 2
const ESCAPE_BASE := 0.15
const ESCAPE_PER_CREW := 0.08
const ESCAPE_PER_TIER := 0.05
const ESCAPE_FAIL_DAYS := 2
const LOYALTY_SLIP := 0.06
const CONNECT_STANDING := 0.15

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if state.prison_until_tick <= 0:
			if state.prison_connections > 0:
				_out_with_connections(state, me, tick)
			continue
		if state.ui_prison != "":
			state.prison_choice = state.ui_prison
			state.ui_prison = ""
		if tick % SimClock.TICKS_PER_SECOND != PHASE:
			continue
		var day := HustleSystem.day_of(tick)
		if state.prison_day == day:
			continue
		state.prison_day = day
		day_inside(_world, state, me, tick)

## One prison day: the choice you made, then the news from outside.
static func day_inside(world: World, state: PlayerStateData, me: NPCData, tick: int) -> String:
	var said := ""
	match state.prison_choice:
		"head_down":
			state.prison_good += 1
			if state.prison_good >= GOOD_DAYS:
				state.prison_good = 0
				state.prison_until_tick -= SimClock.day_ticks
				said = "Good behaviour: a day off your time."
			else:
				said = "Another quiet day."
		"yard":
			Wallet.earn_clean(world, YARD_PAY)
			Skills.train(world, state, &"melee", 6.0)
			said = "Yard work: $%d and stronger." % YARD_PAY
		"connections":
			state.prison_connections += 1
			said = "You made a friend inside. That counts out there."
		"appeal":
			if me.cash - state.dirty_cash >= APPEAL_COST:
				Wallet.spend(world, APPEAL_COST)
				state.prison_until_tick -= APPEAL_DAYS * SimClock.day_ticks
				said = "The lawyer earned it: %d days off." % APPEAL_DAYS
			else:
				said = "The lawyer wants $%d clean. You don't have it." % APPEAL_COST
			state.prison_choice = "head_down"
		"escape":
			state.prison_choice = "head_down"
			if world.runtime_rng.randf() < escape_odds(world, state):
				state.prison_until_tick = tick   # out tonight
				state.law_tier = GanstoidEnums.LawTier.INVESTIGATED
				state.case_evidence = CaseSystem.WARRANT_AT + 10.0
				StampView.put(state, "ESCAPED", "lie low: they're looking for you", UiTheme.GOOD)
				said = "Over the wall. Every cop in the city has your face."
			else:
				state.prison_until_tick += ESCAPE_FAIL_DAYS * SimClock.day_ticks
				said = "Caught at the fence. %d more days." % ESCAPE_FAIL_DAYS
	var slip := LOYALTY_SLIP * (0.4 if state.crib >= CribSystem.HANGOUT_TIER else 1.0)
	for id in state.crew_ids:
		var e: Entity = world.entities.get(id)
		var c: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if c != null:
			c.loyalty = maxf(0.0, c.loyalty - slip)
	var left := maxf(0.0, float(state.prison_until_tick - tick) / SimClock.day_ticks)
	PhoneSystem.push(world, state, "Inside", "%s %.1f days left. Your crew is %s." % [said, left, "holding up" if slip < LOYALTY_SLIP else "getting restless"])
	return said

static func escape_odds(world: World, state: PlayerStateData) -> float:
	var crew := 0
	for id in state.crew_ids:
		var e: Entity = world.entities.get(id)
		crew += int(e != null and not (e.get_component(ComponentNames.NPC) as NPCData).is_down)
	return clampf(ESCAPE_BASE + ESCAPE_PER_CREW * crew + ESCAPE_PER_TIER * Rep.tier(state), 0.0, 0.8)

## Out: the friends you made pay off.
func _out_with_connections(state: PlayerStateData, me: NPCData, tick: int) -> void:
	var n := state.prison_connections
	state.prison_connections = 0
	for g in state.gang_standing.keys():
		state.gang_standing[g] = minf(1.0, float(state.gang_standing[g]) + CONNECT_STANDING * n)
	for e in _world.get_entities_with_component(ComponentNames.GANG).values():
		var gid: StringName = (e.get_component(ComponentNames.GANG) as GangData).id
		if not state.gang_standing.has(gid):
			state.gang_standing[gid] = minf(1.0, 0.5 + CONNECT_STANDING * n)
	if state.heist.is_empty() and state.rank >= HeistSystem.MIN_RANK:
		HeistSystem.offer(_world, state, me, tick)
	PhoneSystem.push(_world, state, "A friend from inside", "Heard you're out. The gangs know your name now, and I've got work if you want it.")

static func choice_text(c: String) -> String:
	return {"head_down": "Keep your head down (good behaviour cuts time)", "yard": "Work the yard ($%d, stronger)" % YARD_PAY,
		"connections": "Make connections (gangs and work when you're out)", "appeal": "Pay a lawyer ($%d clean, %d days off)" % [APPEAL_COST, APPEAL_DAYS],
		"escape": "Try to escape (fail: %d more days)" % ESCAPE_FAIL_DAYS}[c]
