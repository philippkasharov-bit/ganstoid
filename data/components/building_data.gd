## Data contract for any building in the sim — residence, business front, safehouse.
## Pure data; economy system (Phase 2) reads/writes cash_on_hand and revenue.
class_name BuildingData
extends Resource

@export var id: StringName
@export var building_type: GanstoidEnums.BuildingType
@export var position: Vector2

## Which city zone this lot fell in at generation time (CityGenerator).
## Stored, not recomputed — same pattern as everything else hardening
## pulled out of "figure it out live" and into "figure it out once,
## remember it" (RecognitionSystem, EconomyItemData.demand/supply).
@export var zone: GanstoidEnums.CityZone = GanstoidEnums.CityZone.SPRAWL

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

## Batch 10 (locked): a general "how much witnessed crime has happened
## near here lately" scalar — not robbery-specific like has_been_hit, bumped
## by ANY witnessed-and-recognized crime nearby (CrimeSystem.broadcast_
## witnesses), decayed back toward 0.0 by EconomySystem. Drives CopAISystem's
## patrol bias toward "high crime places" generally, and — combined with
## is_raidable below — whether a full raid can trigger there at all.
@export_range(0.0, 1.0) var crime_heat: float = 0.0

## Batch 19: world tick this business last paid your muscle protection
## money -- they pay at most once per CrewMuscleSystem.PROTECTION_COOLDOWN_TICKS.
@export var protection_paid_tick: int = -1000000

## Batch 25: weed sitting in your grow house waiting to be picked up.
@export var stored_product: int = 0

## R1: what a LEGIT_BUSINESS physically is: &"shop" (retail: commercial
## buildings) or &"workshop" (warehouses, garages, workshops -- never retail).
## Empty for every other role.
@export var business_kind: StringName = &""
