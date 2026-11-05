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
@export_range(0.0, 1.0) var demand: float = 0.5
@export_range(0.0, 1.0) var supply: float = 0.5

## True for drug-trade / stolen-goods items — these don't appear in
## legitimate business inventories and raise heat if sold in public.
@export var is_illegal: bool = false
