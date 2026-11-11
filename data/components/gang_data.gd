## Data contract for a rival gang faction.
## influence is the stat the player degrades by attacking turf/members/business
## (Phase 4 Beef Ladder) — reaching 0 zeroes out any standing CONTRACT tier
## against the player. Decay/combat logic lives in the heat system, not here.
class_name GangData
extends Resource

@export var id: StringName
@export var display_name: String

@export_range(0.0, 1.0) var influence: float = 1.0
@export var cash: int = 0

@export var territory_building_ids: Array[StringName] = []
@export var member_npc_ids: Array[StringName] = []

## True once influence has been driven to 0 — contract against the player
## (if any) is permanently cleared when this flips.
@export var is_destroyed: bool = false
@export var armory: int = 0   # WP1: guns you sold them (clean ones count double): they shoot straighter, win more fights
