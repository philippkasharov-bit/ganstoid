## Data contract for any NPC (civilian, crew member, cop, rival).
## Pure data — no behavior. Systems (Phase 0 batch 2) read/write these fields;
## this resource never decides anything about what happens to them.
class_name NPCData
extends Resource

@export var id: StringName
@export var display_name: String
@export var position: Vector2

## --- Needs (Zomboid-style survival layer, lighter weight) ---
@export_range(0.0, 1.0) var hunger: float = 1.0
@export_range(0.0, 1.0) var fatigue: float = 1.0
@export_range(0.0, 1.0) var stress: float = 0.0

## --- Schedule ---
## Building ids (from BuildingData.id) this NPC routes between daily.
@export var home_building_id: StringName
@export var work_building_id: StringName

## --- Economy ---
@export var cash: int = 0

## --- Crew (only meaningful if recruited; player's crew only) ---
@export var is_crew: bool = false
@export var crew_role: GanstoidEnums.CrewRole = GanstoidEnums.CrewRole.MUSCLE
@export_range(0.0, 1.0) var loyalty: float = 0.5

## --- Witness memory ---
## Each entry: {event_type: StringName, witnessed_at: int (tick), severity: float}.
## Drives snitch risk; decays/forgets over time in the witness system.
@export var witnessed_events: Array[Dictionary] = []

## --- Escalation (only meaningful for the player character) ---
@export var law_tier: GanstoidEnums.LawTier = GanstoidEnums.LawTier.CLEAN
## faction_id (StringName) -> GanstoidEnums.BeefTier
@export var beef_tiers: Dictionary = {}
