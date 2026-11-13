## Data contract for any building in the sim — residence, business front, safehouse.
## Pure data; economy system (Phase 2) reads/writes cash_on_hand and revenue.
class_name BuildingData
extends Resource

@export var id: StringName
## PF1: false for a building exactly as the seed made it (the save skips it,
## like an untouched parked car). Any field written sets it; container edits
## set it in Containers. Not saved itself.
var touched := true
@export var building_type: GanstoidEnums.BuildingType:
	set(v):
		if v != building_type:
			touched = true
		building_type = v
@export var position: Vector2:
	set(v):
		if v != position:
			touched = true
		position = v

## Which city zone this building stands in, set at new-game start (CityRoles).
## Stored, not recomputed — same pattern as everything else hardening
## pulled out of "figure it out live" and into "figure it out once,
## remember it" (RecognitionSystem, EconomyItemData.demand/supply).
@export var zone: GanstoidEnums.CityZone = GanstoidEnums.CityZone.SPRAWL:
	set(v):
		if v != zone:
			touched = true
		zone = v

## Empty if unowned (civilian-only residences, unclaimed fronts).
@export var owner_npc_id: StringName = &"":
	set(v):
		if v != owner_npc_id:
			touched = true
		owner_npc_id = v

## Drives per-building economy feedback loop (Phase 2): robbed buildings
## deplete cash_on_hand and regenerate toward daily_revenue over time.
@export var cash_on_hand: int = 0:
	set(v):
		if v != cash_on_hand:
			touched = true
		cash_on_hand = v
@export var daily_revenue: int = 0:
	set(v):
		if v != daily_revenue:
			touched = true
		daily_revenue = v

## Safehouses/fronts only — can rivals or cops raid this location.
@export var is_raidable: bool = false:
	set(v):
		if v != is_raidable:
			touched = true
		is_raidable = v

## Set true once this building has been robbed/raided at least once —
## drives "corner gets poorer/more guarded" feedback (Phase 2).
@export var has_been_hit: bool = false:
	set(v):
		if v != has_been_hit:
			touched = true
		has_been_hit = v

## Batch 10 (locked): a general "how much witnessed crime has happened
## near here lately" scalar — not robbery-specific like has_been_hit, bumped
## by ANY witnessed-and-recognized crime nearby (CrimeSystem.broadcast_
## witnesses), decayed back toward 0.0 by EconomySystem. Drives CopAISystem's
## patrol bias toward "high crime places" generally, and — combined with
## is_raidable below — whether a full raid can trigger there at all.
@export_range(0.0, 1.0) var crime_heat: float = 0.0:
	set(v):
		if v != crime_heat:
			touched = true
		crime_heat = v

## Batch 19: world tick this business last paid your muscle protection
## money -- they pay at most once per CrewMuscleSystem.PROTECTION_COOLDOWN_TICKS.
@export var protection_paid_tick: int = -1000000:
	set(v):
		if v != protection_paid_tick:
			touched = true
		protection_paid_tick = v

## Batch 25: weed sitting in your grow house waiting to be picked up.
@export var stored_product: int = 0:
	set(v):
		if v != stored_product:
			touched = true
		stored_product = v

## R1: what a LEGIT_BUSINESS physically is: &"shop" (retail: commercial
## buildings) or &"workshop" (warehouses, garages, workshops -- never retail).
## Empty for every other role.
@export var business_kind: StringName = &"":
	set(v):
		if v != business_kind:
			touched = true
		business_kind = v
@export var product: StringName = &"weed":   # DR1: what your safehouse makes (ProductionSystem.RECIPES)
	set(v):
		if v != product:
			touched = true
		product = v
@export var looted_tick: int = -1000000:   # X2: last burgled (houses restock in a few days)
	set(v):
		if v != looted_tick:
			touched = true
		looted_tick = v
## DW2: doors and windows. A kicked-in door or a smashed window stays that way
## until the place is fixed up (RESTOCK_DAYS after the break-in); boarded
## windows (your own place) cannot be smashed.
@export var door_kicked: bool = false:
	set(v):
		if v != door_kicked:
			touched = true
		door_kicked = v
@export var windows_broken: int = 0:
	set(v):
		if v != windows_broken:
			touched = true
		windows_broken = v
@export var windows_boarded: bool = false:
	set(v):
		if v != windows_boarded:
			touched = true
		windows_boarded = v
## LT1: what is inside: container kind -> {"items": {id: n}, "filled": bool, "emptied_tick": int}.
## Filled on first opening; "stash" is your own, never rolled.
## E1: money that is not in the till or the drawers. A business: its bank
## balance (pays wages, rent, restock). A home: the household's savings.
## cash_on_hand is the till for a business and the cash kept at home for a home.
@export var bank: int = 0:
	set(v):
		if v != bank:
			touched = true
		bank = v
## E1: 0 none, 1 a camera and a bat under the counter, 2 a guard or a gun, 3 armed guard.
@export var security: int = 0:
	set(v):
		if v != security:
			touched = true
		security = v
## E1: 0 open, 1 struggling (cut staff), 2 closed (bust or boarded up).
@export var status: int = 0:
	set(v):
		if v != status:
			touched = true
		status = v
@export var containers: Dictionary = {}:
	set(v):
		if v != containers:
			touched = true
		containers = v
