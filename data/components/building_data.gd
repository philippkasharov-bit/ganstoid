## Data contract for any building in the sim — residence, business front, safehouse.
## Pure data; economy system (Phase 2) reads/writes cash_on_hand and revenue.
class_name BuildingData
extends Resource

@export var id: StringName
@export var building_type: GanstoidEnums.BuildingType
@export var position: Vector2

## Empty if unowned (civilian-only residences, unclaimed fronts).
@export var owner_npc_id: StringName = &""

## Drives per-building economy feedback loop (Phase 2): robbed buildings
## deplete cash_on_hand and regenerate toward daily_revenue over time.
@export var cash_on_hand: int = 0
@export var daily_revenue: int = 0

## Safehouses/fronts only — can rivals or cops raid this location.
@export var is_raidable: bool = false

## Set true once this building has been robbed/raided at least once —
## drives "corner gets poorer/more guarded" feedback (Phase 2).
@export var has_been_hit: bool = false
