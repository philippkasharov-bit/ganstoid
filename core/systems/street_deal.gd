## LT4: dealing hand to hand. E by anyone on the street: "Sell them weed".
## Not everyone uses: more do on poor blocks, a regular always does. Those
## who use buy at your asking price as DrugLabSystem.accept says (QL3), pay
## dirty cash, and remember the quality (good makes regulars, trash makes
## enemies). Each deal is a crime anyone around can see. Ask someone once a
## day at most.
class_name StreetDeal
extends RefCounted

const USER_BASE := 0.2
const USER_POOR := 0.35        # more users on a poor block (1 - wealth) x this
const ASK_AGAIN_H := 24.0

static func sell(world: World, me: NPCData, state: PlayerStateData, buyer: NPCData, good: StringName) -> Dictionary:
	if int(state.inventory.get(good, 0)) <= 0:
		return {"ok": false, "reason": "nothing_to_sell"}
	if world.tick < int(state.dealt.get(buyer.id, -1000000)) + SimClock.hours(ASK_AGAIN_H):
		return {"ok": false, "reason": "already_refused"}
	state.dealt[buyer.id] = world.tick
	var rng := world.runtime_rng
	var regular := MemorySystem.feel_of(state, buyer.id) >= CrewDealerSystem.REGULAR_AT
	var wealth := float(BlockEconomyData.block_at(world, buyer.position).get("wealth", 0.5))
	if not regular and rng.randf() >= USER_BASE + USER_POOR * (1.0 - wealth):
		return {"ok": false, "reason": "not_a_buyer"}
	var worth := DrugLabSystem.value_each(world, state, good, buyer.position, false)
	var ask := DrugLabSystem.ask_each(world, state, good, buyer.position, false)
	if rng.randf() >= DrugLabSystem.accept(ask / (CrewDealerSystem.REGULAR_PAYS if regular else 1.0), worth):
		return {"ok": false, "reason": "too_dear"}
	state.inventory[good] = int(state.inventory[good]) - 1
	if int(state.inventory[good]) <= 0:
		state.inventory.erase(good)
	Wallet.earn_dirty(world, ask)
	var q := DrugLabSystem.stars(state, good)
	if q >= 4.0 or (q >= 3.0 and ask <= worth * 0.85):
		MemorySystem.remember(world, state, buyer.id, "good_product")
	elif q < 2.0:
		MemorySystem.remember(world, state, buyer.id, "bad_batch")
	if good == GrowSystem.GOOD_ID:
		GrowSystem.sold(world, state)
	Skills.train(world, state, &"hustle", 2.0)
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED])
	return {"ok": true, "effect": "sold_hand", "amount": ask}
