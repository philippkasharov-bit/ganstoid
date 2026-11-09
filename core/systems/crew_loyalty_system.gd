## Phase 3 batch 16: crew loyalty and (very rare) snitching.
##
## Loyalty (NPCData.loyalty, reserved since Phase 0):
##   - rises each time the crew takes its cut of a score (take_cut),
##   - slowly fades when they go unpaid (neglect, every warm tick),
##   - takes a hit whenever the player gets arrested (on_player_arrested).
##
## Snitching -- the roadmap's locked Phase 3 formula,
## snitch_risk = clamp(1 - loyalty, 0, 1) * SNITCH_RISK_COEFFICIENT,
## rolled per crew member per warm tick ONLY while the player already has
## heat (law_tier above CLEAN). Phil's call: very rare. At neutral loyalty a
## single crew member snitches on roughly 2% of heat episodes; a loyal one
## (0.9) well under 0.5%; fully loyal never.
##
## Evidence-gate note (top-of-roadmap constraint): this is the one
## deliberately-scoped exception to "only a witnessed+recognized crime
## triggers law response". It can only fire when that gate has ALREADY
## fired (heat > CLEAN), and it feeds the same single CRIME_WITNESSED event
## rather than a new law path -- an insider extending existing evidence,
## never a proximity check and never heat out of nothing.
class_name CrewLoyaltySystem
extends SystemBase

## Share of every score the crew takes, split evenly between members.
const CREW_CUT_FRACTION := 0.1
const LOYALTY_GAIN_PER_CUT := 0.06
## Multiplicative fade toward 0 per warm tick unpaid (~4 game days to halve).
const NEGLECT_DECAY := 0.001
## Fraction of loyalty kept after the player gets arrested.
const ARREST_LOYALTY_KEEP := 0.85
const SNITCH_RISK_COEFFICIENT := 0.0006
const SNITCH_SEVERITY := 0.5

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.WARM
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, _tick: int) -> void:
	for player in entities.values():
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		for crew_id in state.crew_ids.duplicate():  # snitch() mutates crew_ids
			var npc := _crew_npc(_world, crew_id)
			if npc == null:
				continue
			npc.loyalty += (0.0 - npc.loyalty) * NEGLECT_DECAY
			if state.law_tier != GanstoidEnums.LawTier.CLEAN and _world.runtime_rng.randf() < snitch_chance(npc.loyalty):
				snitch(_world, state, crew_id)

static func snitch_chance(loyalty: float) -> float:
	return clampf(1.0 - loyalty, 0.0, 1.0) * SNITCH_RISK_COEFFICIENT

## Crew take CREW_CUT_FRACTION of whatever the player just earned. Paid out
## of the player's own cash into each member's NPCData.cash -- real money
## moving, never conjured. Returns the total cut taken.
static func take_cut(world: World, state: PlayerStateData, result: Dictionary) -> int:
	if state.crew_ids.is_empty() or not result.get("ok", false) or result.get("effect", "") == "buy":
		return 0
	var earned := 0
	for field in ["proceeds", "stolen", "taken", "payout"]:
		earned += int(result.get(field, 0))
	var share := int(floor(earned * CREW_CUT_FRACTION / state.crew_ids.size()))
	if share <= 0:
		return 0
	var total := 0
	for crew_id in state.crew_ids:
		var npc := _crew_npc(world, crew_id)
		if npc == null:
			continue
		Wallet.spend(world, share)  # batch 24: the cut comes out of the (dirty) score
		npc.cash += share
		npc.loyalty += (1.0 - npc.loyalty) * LOYALTY_GAIN_PER_CUT
		total += share
	return total

static func on_player_arrested(world: World, state: PlayerStateData) -> void:
	for crew_id in state.crew_ids:
		var npc := _crew_npc(world, crew_id)
		if npc != null:
			npc.loyalty *= ARREST_LOYALTY_KEEP

## The snitch walks out of the crew and talks: one CRIME_WITNESSED at the
## player's position, through the same event every other law consequence
## listens to.
static func snitch(world: World, state: PlayerStateData, crew_id: StringName) -> void:
	var npc := _crew_npc(world, crew_id)
	state.crew_ids.erase(crew_id)
	if npc != null:
		npc.is_crew = false
		npc.recruit_refused = true
	var player_npc: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	StreetTalk.say_key(world, state, "snitched")
	world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {
		"position": player_npc.position,
		"severity": SNITCH_SEVERITY,
		"tick": world.tick,
		"witness_id": crew_id,
	})

static func _crew_npc(world: World, crew_id: StringName) -> NPCData:
	var entity: Entity = world.entities.get(crew_id)
	return null if entity == null else entity.get_component(ComponentNames.NPC)

## Batch 19: hand a posted crew member's held earnings (dealer sales,
## muscle collections) to the player minus their cut. Returns the payout.
static func pay_out_earnings(world: World, npc: NPCData) -> int:
	var cut := int(floor(npc.crew_earnings * CREW_CUT_FRACTION))
	var payout := npc.crew_earnings - cut
	Wallet.earn_dirty(world, payout)  # batch 24: corner/protection money is dirty
	npc.cash += cut
	if npc.crew_earnings > 0:
		npc.loyalty += (1.0 - npc.loyalty) * LOYALTY_GAIN_PER_CUT
	npc.crew_earnings = 0
	return payout
