## The drug-deal buy/sell action -- the player-facing feature the Phase 2
## economy core was built to support. Static utility, same shape as
## CrimeSystem (discrete player-triggered action, not a per-tick process).
##
## Only one good is wired to the interaction this phase (&"weed", hardcoded
## at the call site in PlayerInputSystem) -- there's no good-selection UI
## yet to pick from GoodsCatalog's full list, so building that selection
## now would be UI for a choice the player can't meaningfully make. Pills
## stay in the catalog, priced and ready, for whenever that UI exists.
##
## Batch 7 (locked): buy/sell are also what give EconomyItemData.
## player_market_reputation its payoff (reserved since Phase 0, decayed by
## EconomySystem since this same batch) -- a trusted repeat buyer/seller
## in a good gets a small, reputation-scaled price edge, and each
## completed trade nudges reputation a bit further toward trusted. See
## _buy_price_multiplier/_sell_price_multiplier below.
##
## Batch 8 (locked): a SECOND, independent price edge stacks on top of
## batch 7's -- standing with WHO you're dealing with, not just WHAT good.
## A gang-affiliated dealer reads PlayerStateData.gang_standing for their
## gang_id; a solo (no gang_id) reads PlayerStateData.solo_standing for
## their own NPC id. Same multiplier shape and same REPUTATION_* constants'
## sibling (RELATIONSHIP_*) as batch 7, just scoped to a relationship
## instead of a market. The two multiply together rather than picking one
## -- being a known weed buyer AND on good terms with this particular gang
## are both real, separately-earned trust, and should both pay off.
class_name DealSystem
extends RefCounted

## Fixed at 1 per button press for the same reason only one good is wired
## up -- no quantity selector exists yet. TRADE_QUANTITY, not a magic 1
## inline at both call sites, so a future bulk-buy feature changes one
## constant instead of hunting for the literal.
const TRADE_QUANTITY := 1

## How hard one buy nudges demand up (fed into EconomySystem.record_trade,
## which applies the locked diminishing-returns shape -- these are not a
## flat price delta, see EconomySystem's doc comment).
const BUY_PRESSURE := 0.15

## Selling to a dealer is the mirror of buying, but EconomySystem.record_trade
## only drains supply (its one caller, a buy, needs exactly that) -- it has
## no "sell" mode that raises supply, so a sell applies its own bump
## directly here rather than overloading record_trade's documented contract
## with a sign-flipped argument. Same diminishing-returns shape either way.
const SELL_SUPPLY_BUMP := 0.15
const SELL_DEMAND_EASE := 0.1

## Batch 7 (locked): the actual payoff for EconomyItemData.player_market_
## reputation (reserved since Phase 0, decayed by EconomySystem since
## batch 7, previously read by nothing). A trusted repeat buyer/seller in
## a given good gets a small price edge -- cheaper buys, better sell
## proceeds -- that fades back to neutral over a dry spell (see
## EconomySystem.REPUTATION_DECAY), rather than being a flat loyalty
## discount with no cost to letting the relationship lapse.
## REPUTATION_PRICE_SWING is the max fraction current_price can move
## either direction at the two reputation extremes (0.0 or 1.0) -- 0.5
## (neutral/no history) always prices at current_price exactly.
const REPUTATION_PRICE_SWING := 0.1
## How hard one completed trade nudges reputation toward 1.0 -- same
## diminishing-returns shape as everything else in this phase
## (RecognitionSystem.recognition_chance, EconomySystem's demand/supply).
const REPUTATION_GAIN_PER_TRADE := 0.08

## Batch 8 (locked): wider swing than REPUTATION_PRICE_SWING (0.1) --
## standing with a specific gang or solo is meant to read as the stronger,
## more personal edge of the two stacked discounts, market reputation the
## weaker/more impersonal one. Same neutral-at-0.5, no-op-when-untouched
## shape otherwise.
const RELATIONSHIP_PRICE_SWING := 0.15
const RELATIONSHIP_GAIN_PER_TRADE := 0.08

## Batch 11: a deal is no longer instant. start_handoff roots the player and
## the dealer for HANDOFF_TICKS (~3 sim-seconds at 60 ticks/sec); halfway
## through, the exchange is witnessable once more on top of the usual roll
## at completion. Longer exposure = more chances to be seen, still only
## through broadcast_witnesses -- no new trigger (evidence-gated law).
const HANDOFF_TICKS := 180

## Batch 12: a completed deal can still go wrong -- the dealer shorts you.
## Chance scales with your standing with that dealer's gang (or that solo):
## RIPOFF_MAX_CHANCE at standing 0.0, half that at neutral 0.5, never at
## 1.0. A shorted buy charges you and hands over nothing; a shorted sell
## takes your product and pays RIPOFF_SELL_PAYOUT_FRACTION of the price.
## Standing/reputation still move as normal -- from the dealer's side the
## trade happened; getting burned is the price of dealing with strangers.
const RIPOFF_MAX_CHANCE := 0.3
const RIPOFF_SELL_PAYOUT_FRACTION := 0.5

const HUSTLE_EDGE := 0.02   # S1: 2% better prices per hustle level

static func ripoff_chance(standing: float) -> float:
	return RIPOFF_MAX_CHANCE * clampf(1.0 - standing, 0.0, 1.0)
const EXPOSURE_CHECK_AT_TICKS_LEFT := 90

static func start_handoff(world: World, dealer_id: StringName, good_id: StringName, kind: String) -> Dictionary:
	var ctx := _resolve_deal(world, dealer_id, good_id)
	if not ctx.get("ok", false):
		return ctx
	var player_state: PlayerStateData = ctx["player_state"]
	if not player_state.pending_deal.is_empty():
		return {"ok": false, "reason": "already_dealing"}
	if kind == "sell" and player_state.inventory.get(good_id, 0) < TRADE_QUANTITY:
		return {"ok": false, "reason": "nothing_to_sell"}
	var dealer_npc: NPCData = ctx["dealer_npc"]
	dealer_npc.is_busy = true
	player_state.pending_deal = {"dealer_id": dealer_id, "good_id": good_id, "kind": kind, "ticks_left": HANDOFF_TICKS}
	return {"ok": true, "effect": "handoff_started"}

## Batch 11: abandons an in-progress handoff with no trade -- used when the
## player is arrested mid-deal. Safe to call with nothing pending.
static func cancel_handoff(world: World, player_state: PlayerStateData) -> void:
	if player_state.pending_deal.is_empty():
		return
	var dealer_entity: Entity = world.entities.get(player_state.pending_deal["dealer_id"])
	if dealer_entity != null:
		dealer_entity.get_component(ComponentNames.NPC).is_busy = false
	player_state.pending_deal = {}

## Called every HOT tick by PlayerInputSystem while a handoff is pending.
## Returns {} until the handoff finishes, then the buy/sell result.
static func advance_handoff(world: World, player_npc: NPCData, player_state: PlayerStateData) -> Dictionary:
	var deal := player_state.pending_deal
	deal["ticks_left"] -= 1
	if deal["ticks_left"] == EXPOSURE_CHECK_AT_TICKS_LEFT:
		CrimeSystem.broadcast_witnesses(world, player_npc.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED])
	if deal["ticks_left"] > 0:
		return {}
	player_state.pending_deal = {}
	var dealer_entity: Entity = world.entities.get(deal["dealer_id"])
	if dealer_entity != null:
		dealer_entity.get_component(ComponentNames.NPC).is_busy = false
	if deal["kind"] == "buy":
		return buy(world, deal["dealer_id"], deal["good_id"])
	return sell(world, deal["dealer_id"], deal["good_id"])

static func buy(world: World, dealer_id: StringName, good_id: StringName) -> Dictionary:
	var ctx := _resolve_deal(world, dealer_id, good_id)
	if not ctx.get("ok", false):
		return ctx
	var player_npc: NPCData = ctx["player_npc"]
	var item: EconomyItemData = ctx["item"]

	var player_state: PlayerStateData = ctx["player_state"]
	var dealer_npc: NPCData = ctx["dealer_npc"]
	var mult := _buy_price_multiplier(item.player_market_reputation) * _relationship_buy_multiplier(_relationship(dealer_npc, player_state)) * (1.0 - HUSTLE_EDGE * Skills.level(player_state, &"hustle"))
	var cost: int = maxi(1, int(round(item.current_price * TRADE_QUANTITY * mult)))
	if player_npc.cash < cost:
		return {"ok": false, "reason": "cant_afford"}

	var ripped_off := world.runtime_rng.randf() < ripoff_chance(_relationship(dealer_npc, player_state))
	Wallet.spend(world, cost)  # batch 24: dirty money first
	if not ripped_off:
		player_state.inventory[good_id] = player_state.inventory.get(good_id, 0) + TRADE_QUANTITY
	EconomySystem.record_trade(item, BUY_PRESSURE, 0.0)
	item.player_market_reputation += (1.0 - item.player_market_reputation) * REPUTATION_GAIN_PER_TRADE
	_bump_relationship(dealer_npc, player_state)
	Skills.train(world, player_state, &"hustle", 3.0)
	CrimeSystem.broadcast_witnesses(world, player_npc.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED])
	return {"ok": true, "effect": "buy", "good_id": good_id, "quantity": 0 if ripped_off else TRADE_QUANTITY, "cost": cost, "ripped_off": ripped_off}

static func sell(world: World, dealer_id: StringName, good_id: StringName) -> Dictionary:
	var ctx := _resolve_deal(world, dealer_id, good_id)
	if not ctx.get("ok", false):
		return ctx
	var player_state: PlayerStateData = ctx["player_state"]
	var held: int = player_state.inventory.get(good_id, 0)
	if held < TRADE_QUANTITY:
		return {"ok": false, "reason": "nothing_to_sell"}

	var player_npc: NPCData = ctx["player_npc"]
	var item: EconomyItemData = ctx["item"]
	var dealer_npc: NPCData = ctx["dealer_npc"]
	var mult := _sell_price_multiplier(item.player_market_reputation) * _relationship_sell_multiplier(_relationship(dealer_npc, player_state)) * (1.0 + HUSTLE_EDGE * Skills.level(player_state, &"hustle"))
	var proceeds: int = maxi(1, int(round(item.current_price * TRADE_QUANTITY * mult)))
	var ripped_off := world.runtime_rng.randf() < ripoff_chance(_relationship(dealer_npc, player_state))
	if ripped_off:
		proceeds = maxi(1, int(round(proceeds * RIPOFF_SELL_PAYOUT_FRACTION)))

	player_state.inventory[good_id] = held - TRADE_QUANTITY
	Wallet.earn_dirty(world, proceeds)  # batch 24
	item.supply += (1.0 - item.supply) * SELL_SUPPLY_BUMP
	item.demand -= item.demand * SELL_DEMAND_EASE
	item.player_market_reputation += (1.0 - item.player_market_reputation) * REPUTATION_GAIN_PER_TRADE
	_bump_relationship(dealer_npc, player_state)
	CrimeSystem.broadcast_witnesses(world, player_npc.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED])
	return {"ok": true, "effect": "sell", "good_id": good_id, "quantity": TRADE_QUANTITY, "proceeds": proceeds, "ripped_off": ripped_off}

## Both multipliers equal 1.0 exactly at reputation == 0.5 (neutral/no
## history) -- a brand-new good's market must price identically to before
## this batch. A trusted buyer (reputation -> 1.0) pays less; a
## trusted seller (reputation -> 1.0) gets paid more -- same reputation
## value drives both, since it tracks the player's standing with this
## good's market as a whole, not separate buyer/seller trust scores.
static func _buy_price_multiplier(reputation: float) -> float:
	return 1.0 + REPUTATION_PRICE_SWING * (0.5 - reputation) * 2.0

static func _sell_price_multiplier(reputation: float) -> float:
	return 1.0 + REPUTATION_PRICE_SWING * (reputation - 0.5) * 2.0

## Batch 8 (locked): same shape as the two above, different swing constant
## -- kept as separate functions rather than parameterizing one shared
## helper with a swing argument, since that would make every call site
## carry an extra "which constant" argument for a two-line formula that's
## cheap to just write twice and name clearly.
static func _relationship_buy_multiplier(standing: float) -> float:
	return 1.0 + RELATIONSHIP_PRICE_SWING * (0.5 - standing) * 2.0

static func _relationship_sell_multiplier(standing: float) -> float:
	return 1.0 + RELATIONSHIP_PRICE_SWING * (standing - 0.5) * 2.0

## Batch 8 (locked): resolves which standing value governs pricing for
## this dealer -- the whole gang's standing if they're affiliated, this one
## NPC's own standing if they're a solo. Read-only; _bump_relationship is
## the writer, kept separate so a future caller (price preview UI, say)
## can read this without accidentally nudging the relationship just by
## asking what it currently is.
static func _relationship(dealer_npc: NPCData, player_state: PlayerStateData) -> float:
	if dealer_npc.gang_id != &"":
		return player_state.gang_standing.get(dealer_npc.gang_id, 0.5)
	return player_state.solo_standing.get(dealer_npc.id, 0.5)

## Same diminishing-returns nudge as player_market_reputation's, applied to
## whichever dictionary _relationship above would have read from.
static func _bump_relationship(dealer_npc: NPCData, player_state: PlayerStateData) -> void:
	if dealer_npc.gang_id != &"":
		var gang_standing: float = player_state.gang_standing.get(dealer_npc.gang_id, 0.5)
		player_state.gang_standing[dealer_npc.gang_id] = gang_standing + (1.0 - gang_standing) * RELATIONSHIP_GAIN_PER_TRADE
	else:
		var solo_standing: float = player_state.solo_standing.get(dealer_npc.id, 0.5)
		player_state.solo_standing[dealer_npc.id] = solo_standing + (1.0 - solo_standing) * RELATIONSHIP_GAIN_PER_TRADE

## Shared precondition checks for buy/sell -- player exists, dealer exists
## and is close enough, good exists in the catalog. Returns the resolved
## pieces both actions need so neither repeats the lookup chain, or an
## {"ok": false, "reason": ...} matching the same shape CrimeSystem's
## actions return on failure.
static func _resolve_deal(world: World, dealer_id: StringName, good_id: StringName) -> Dictionary:
	var player_entity := _get_player_entity(world)
	if player_entity == null:
		return {"ok": false, "reason": "no_player"}
	if not world.entities.has(dealer_id):
		return {"ok": false, "reason": "no_dealer"}
	var dealer_entity: Entity = world.entities[dealer_id]
	var dealer_npc: NPCData = dealer_entity.get_component(ComponentNames.NPC)
	if dealer_npc == null or not dealer_npc.is_dealer:
		return {"ok": false, "reason": "not_a_dealer"}

	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	if dealer_npc.position.distance_to(player_npc.position) > CrimeSystem.INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if not world.economy_items.has(good_id):
		return {"ok": false, "reason": "no_such_good"}

	return {
		"ok": true,
		"player_npc": player_npc,
		"player_state": player_entity.get_component(ComponentNames.PLAYER_STATE),
		"item": world.economy_items[good_id],
		"dealer_npc": dealer_npc,
	}

static func _get_player_entity(world: World) -> Entity:
	var matches := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	for entity in matches.values():
		return entity
	return null
