## CR1: your crib. Home starts as a mattress on the floor; you spend money (and
## need the rank) to make it more:
##   0 Mattress       where you start
##   1 Pad            $600:    sleep at home rests you a third faster
##   2 Spot           $2000, Soldier: a safe (an arrest takes half as much),
##                    a workbench (fix your weapon at home for free), crew hang
##                    out (their loyalty grows every day)
##   3 Stash house    $6000, Lieutenant: trophies from your big scores (each
##                    keeps your name known), and a little dirty money is
##                    cleaned at home every morning (a fee)
## Upgrade at your front door (E) or from the phone's Crib app; a request
## (ui_crib) this system carries out. Saved: crib, trophies.
class_name CribSystem
extends SystemBase

const PHASE := 47
const TIERS := ["Mattress", "Pad", "Spot", "Stash house"]
const COST := [0, 600, 2000, 6000]
const RANK := [0, 0, 2, 3]
const REST_BONUS := [1.0, 1.33, 1.33, 1.5]
const SAFE_TIER := 2
const BENCH_TIER := 2
const HANGOUT_TIER := 2
const HANGOUT_LOYALTY := 0.05     # per game day, each crew member
const TROPHY_TIER := 3
const TROPHY_FAME := 1.0          # per trophy, per morning (keeps your name known)
const LAUNDER_TIER := 3
const LAUNDER_PER_DAY := 300
const LAUNDER_FEE := 0.15

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
		if state.ui_crib:
			state.ui_crib = false
			StreetTalk.say(_world, state, upgrade(_world, state))
		if tick % SimClock.TICKS_PER_SECOND != PHASE:
			continue
		var day := HustleSystem.day_of(tick)
		if state.crib_day != day:
			state.crib_day = day
			morning(_world, state)

## Buys the next tier, if you have the money and the rank.
static func upgrade(world: World, state: PlayerStateData) -> Dictionary:
	var next := state.crib + 1
	if next >= TIERS.size():
		return {"ok": false, "reason": "crib_max"}
	if state.rank < RANK[next]:
		return {"ok": false, "reason": "crib_rank"}
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if me.cash < COST[next]:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, COST[next])
	state.crib = next
	StampView.put(state, TIERS[next].to_upper(), "your crib got an upgrade", UiTheme.GOOD)
	return {"ok": true, "effect": "crib_up", "amount": COST[next]}

## Once a game morning: crew hang out, trophies keep your name known, the stash house cleans a little money.
static func morning(world: World, state: PlayerStateData) -> void:
	if state.crib >= HANGOUT_TIER:
		for id in state.crew_ids:
			var e: Entity = world.entities.get(id)
			var c: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if c != null:
				c.loyalty = minf(1.0, c.loyalty + HANGOUT_LOYALTY)
	if state.crib >= TROPHY_TIER and not state.trophies.is_empty():
		state.fame = minf(100.0, state.fame + TROPHY_FAME * state.trophies.size())
	if state.crib >= LAUNDER_TIER and state.dirty_cash > 0:
		var amount := mini(LAUNDER_PER_DAY, state.dirty_cash)
		var fee := int(amount * LAUNDER_FEE)
		state.dirty_cash -= amount
		var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		me.cash -= fee
		PhoneSystem.push(world, state, "Your crib", "Cleaned $%d overnight (fee $%d)." % [amount, fee])

static func rest_mult(state: PlayerStateData) -> float:
	return REST_BONUS[clampi(state.crib, 0, REST_BONUS.size() - 1)]

static func perks(tier: int) -> Array:
	return [[], ["sleep rests you a third faster"], ["a safe: arrests take half as much", "a workbench: fix weapons free", "crew hang out: loyalty grows"],
		["trophies keep your name known", "$%d cleaned every morning" % LAUNDER_PER_DAY, "sleep rests you half as fast again"]][tier]

## A finished score goes on the wall.
static func add_trophy(state: PlayerStateData, what: String, take: int, day: int) -> void:
	state.trophies.append({"what": what, "take": take, "day": day})
