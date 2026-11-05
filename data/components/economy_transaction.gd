## Data contract for a single completed deal between two NPCs (or player<->NPC).
##
## Hardening lock: this is a TRANSIENT value object, never a stored log.
## It's created by whichever system processes a deal, used to update
## EconomyItemData.demand/supply for that tick, and discarded — never
## appended to a growing Array anywhere. An unbounded per-good or per-NPC
## transaction history is the exact same scaling mistake the pre-hardening
## witness-memory design made (see RecognitionSystem); the fix is the same
## shape here: a decaying scalar aggregate (EconomyItemData.demand/supply),
## not an event log queried after the fact.
##
## Scope cut (explicit, not silent): true per-buyer-pair price memory
## ("this NPC remembers it overpaid you last time") is OUT — it would mean
## a Dictionary keyed by buyer id on every good, which is worse than the
## log it would replace. NPC-NPC pairs have no gameplay stakes worth that
## cost. If player-specific reputation is wanted, Phase 2 adds ONE bounded
## scalar to EconomyItemData (how the market as a whole prices dealing with
## the player in that good) — not a per-pair structure.
class_name EconomyTransactionData
extends Resource

@export var buyer_npc_id: StringName
@export var seller_npc_id: StringName
@export var good_id: StringName
@export var quantity: int
@export var price_paid: int
@export var tick: int
