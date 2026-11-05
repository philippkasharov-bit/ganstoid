## Data contract for a single completed deal between two NPCs (or player<->NPC).
## Append-only log entry — per-buyer price elasticity and reputation memory
## (Phase 2) are derived from querying these, never stored redundantly here.
class_name EconomyTransactionData
extends Resource

@export var buyer_npc_id: StringName
@export var seller_npc_id: StringName
@export var good_id: StringName
@export var quantity: int
@export var price_paid: int
@export var tick: int
