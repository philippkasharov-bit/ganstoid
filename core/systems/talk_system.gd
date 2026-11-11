## Talk and bribes (D1 + BR1). Everyone remembers how you treat them:
## NPCData.trust and NPCData.fear (0..1, saved).
##   Small talk   trust up; people who like you share street knowledge
##   Threaten     fear up; a scared witness forgets your face and never calls
##                (it is still a small crime if someone else sees it)
##   Pay off      $PAYOFF: a witness forgets your face; trust up a little
##   Bribe a cop  price rises with your case; each cop has their own price of
##                honesty. Taken: case cut, they stand down. Refused: the
##                honest ones write it up (your case grows).
class_name TalkSystem
extends RefCounted

const PAYOFF := 50
const BRIBE_BASE := 150
const BRIBE_PER_EVIDENCE := 8
const BRIBE_CUT := 40.0
const REFUSED_ADDS := 20.0

static func small_talk(world: World, me: NPCData, who: NPCData) -> Dictionary:
	who.trust = minf(1.0, who.trust + 0.1)
	Traits.deed(world, _state(world), &"talks")
	if who.trust < 0.3:
		return {"ok": true, "effect": "talk_cold"}
	var tip := _tip(world, who)
	return {"ok": true, "effect": "talk_tip", "tip": tip} if tip != "" else {"ok": true, "effect": "talk_warm"}

## Street knowledge: where the nearest fixer or dealer hangs about.
static func _tip(world: World, who: NPCData) -> String:
	var best := ""
	var best_d := 400.0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if (n.is_fixer or n.is_dealer) and not n.is_down and n.position.distance_to(who.position) < best_d:
			best_d = n.position.distance_to(who.position)
			best = "%s about %d m %s of here" % ["A fixer" if n.is_fixer else "A dealer", roundi(best_d), _compass(n.position - who.position)]
	return best

static func _compass(v: Vector2) -> String:
	var dirs := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return dirs[posmod(roundi(v.angle() / (PI / 4.0)), 8)]

static func threaten(world: World, me: NPCData, who: NPCData) -> Dictionary:
	var st := _state(world)
	who.fear = minf(1.0, who.fear + 0.35 * (0.5 if Traits.has(st, &"talker") else 1.0) * (2.0 if Traits.has(st, &"killer") else 1.0))
	who.trust = maxf(0.0, who.trust - 0.2)
	CrimeSystem.broadcast_witnesses(world, me.position, 0.15)
	_silence(world, who)
	return {"ok": true, "effect": "threatened"}

static func pay_off(world: World, me: NPCData, who: NPCData) -> Dictionary:
	var price := int(PAYOFF / Traits.edge(_state(world), &"talker", 1.3))
	if me.cash < price:
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, price)
	who.trust = minf(1.0, who.trust + 0.15)
	_silence(world, who)
	return {"ok": true, "effect": "paid_off", "amount": PAYOFF}

## They forget your face, and a call they were about to make never happens.
static func _silence(world: World, who: NPCData) -> void:
	who.recognition_chance = 0.0
	var calls := world.find_system(WitnessCallSystem) as WitnessCallSystem
	if calls != null:
		calls.cancel(who.id)

static func _state(world: World) -> PlayerStateData:
	return world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)

static func bribe_price(state: PlayerStateData) -> int:
	var p := (BRIBE_BASE + state.case_evidence * BRIBE_PER_EVIDENCE) / Traits.edge(state, &"talker", 1.3)
	return int(p * (1.5 if Traits.has(state, &"killer") else 1.0))

static func bribe_cop(world: World, me: NPCData, state: PlayerStateData, cop: NPCData) -> Dictionary:
	var price := bribe_price(state)
	if me.cash < price:
		return {"ok": false, "reason": "cant_afford"}
	var honesty := NPCRoutine.unit(cop.id, 31)   # fixed per cop: some are on the take, some never
	if honesty > 0.65 - cop.fear * 0.3:
		cop.trust = maxf(0.0, cop.trust - 0.3)
		state.case_evidence += REFUSED_ADDS   # written up: an officer is the witness
		return {"ok": false, "reason": "bribe_refused"}
	Wallet.spend(world, price)
	state.case_evidence = maxf(0.0, state.case_evidence - BRIBE_CUT)
	cop.trust = minf(1.0, cop.trust + 0.2)
	var cops := world.find_system(CopAISystem) as CopAISystem
	if cops != null:
		cops._stand_down(cop.id)
	return {"ok": true, "effect": "bribed", "amount": price}
