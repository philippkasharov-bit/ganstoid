## Data contract for a tradeable good (legal or illegal).
## current_price drifts from base_price via demand/supply in the economy
## system (Phase 2) — this resource never computes that drift itself.
class_name EconomyItemData
extends Resource

@export var good_id: StringName
@export var display_name: String
@export var base_price: int
@export var current_price: int

## 0.0 = no demand, 1.0 = max observed demand. Drives price elasticity.
## These ARE the compressed replacement for transaction history — see the
## hardening lock in economy_transaction.gd. Each processed deal nudges
## these (diminishing-returns rise, passive decay — same shape as
## RecognitionSystem.recognition_chance), rather than a system re-deriving
## price from a queried log of past deals.
@export_range(0.0, 1.0) var demand: float = 0.5
@export_range(0.0, 1.0) var supply: float = 0.5

## Market-wide (not per-buyer) read on dealing with the player in this good —
## the one bounded exception to "no per-buyer memory," since the player is
## the only entity with real gameplay stakes in how the market treats them.
## 0.5 = neutral/no history yet. Phase 2 populates and decays this; Phase 0
## just reserves the field so the data contract doesn't need reshaping later.
@export_range(0.0, 1.0) var player_market_reputation: float = 0.5

## True for drug-trade / stolen-goods items — these don't appear in
## legitimate business inventories and raise heat if sold in public.
@export var is_illegal: bool = false
