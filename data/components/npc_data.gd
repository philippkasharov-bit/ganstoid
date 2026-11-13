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
@export_range(0.0, 1.0) var thirst: float = 1.0   # G2: 1 = not thirsty
@export_range(0.0, 1.0) var stress: float = 0.0

## --- Schedule ---
## Building ids (from BuildingData.id) this NPC routes between daily.
@export var home_building_id: StringName
@export var work_building_id: StringName

## --- Economy ---
@export var cash: int = 0
@export var job: StringName = &""                # E1: "cashier", "mechanic"... (empty: out of work)
@export var wage: int = 0                       # E1: a day's pay, paid by the workplace each payday

## --- Crew (only meaningful if recruited; player's crew only) ---
## Reserved since Phase 0; set by CrewSystem.recruit (batch 15). loyalty is
## consumed by the loyalty/snitch batch.
@export var is_crew: bool = false
@export var crew_role: GanstoidEnums.CrewRole = GanstoidEnums.CrewRole.UNASSIGNED
@export_range(0.0, 1.0) var loyalty: float = 0.5
## Batch 17: where a LOOKOUT was posted (only meaningful for that role).
@export var post_position: Vector2 = Vector2.ZERO
## Batch 18: a crew DEALER's consignment (weed units) and the cash from
## sales they're holding for you until you collect.
@export var crew_stash: int = 0
@export var crew_earnings: int = 0

## True for cop NPCs (PopulationSeeder spawns a fixed handful, on top of
## population_count). CopAISystem drives them instead of NPCScheduleSystem's
## home/work loop — a bool flag, not a separate component, since a cop is
## still fundamentally an NPC with position/cash/etc., just handled by a
## different movement system. Reconsider as a component if cops ever need
## fields no other NPC has.
@export var is_cop: bool = false

## True for dealer NPCs (PopulationSeeder spawns a fixed handful). Unlike
## cops, dealers are NOT skipped by NPCScheduleSystem -- they run the same
## work/home day-cycle as civilians, work_building_id pointing at an
## ILLEGAL_FRONT lot instead of a LEGIT_BUSINESS one. See
## PopulationSeeder._seed_dealers for why (two deliberate play strategies:
## catch them out on the street, or track them down at home). Same
## "bool flag, not a component" reasoning as is_cop.
@export var is_dealer: bool = false
@export var is_fixer: bool = false
## D1: how this person feels about the player (0..1).
@export var car_id: StringName = &""   # V4: the car this person owns (drives on long trips)
@export var trust: float = 0.0
@export var fear: float = 0.0   # JB1: hands out jobs (looks like anyone else)

## Phase 2 batch 8 (locked): which gang (GangData.id) this dealer answers
## to, empty if they're a "solo" -- dealing on their own, no faction behind
## them. Only ever meaningful when is_dealer is true; GangSeeder assigns it
## at seed time. Drives DealSystem's relationship-based pricing: a
## gang-affiliated dealer reads the player's standing with the whole gang
## (PlayerStateData.gang_standing), a solo reads a standing tracked against
## this one NPC specifically (PlayerStateData.solo_standing) -- see
## DealSystem's doc comment for why those are two different dictionaries
## instead of one keyed by "gang id or npc id, whichever applies."
@export var gang_id: StringName = &""

## Batch 11: true while this NPC is mid-handoff in a drug deal with the
## player -- NPCScheduleSystem leaves them standing still until it clears.
@export var is_busy: bool = false

## S1: inside their home or workplace. Not on the street: not drawn, not moved,
## until their schedule sends them out again. (Interiors come later; until then
## "inside" is a state, and the NPC rests on the building's door point.)
@export var indoors: bool = false

## Combat (C1): 1.0 = unhurt. At 0 the person is down for good (permadeath city):
## they stay where they fell and every routine system skips them.
@export_range(0.0, 1.0) var health: float = 1.0
@export var is_down: bool = false
## G3 wounds: a cut or a bullet bleeds until bandaged (or until you bleed out);
## a beating knocks you out instead of killing you: down until ko_until_tick.
@export var bleeding: bool = false
@export var ko_until_tick: int = -1

## Batch 15: this NPC turned down the player's recruitment pitch -- final,
## so the pitch can't be re-rolled until they say yes.
@export var recruit_refused: bool = false

## --- Recognition (witness memory, optimized) ---
## Scalar "does this NPC recognize the player as a criminal" chance, not an
## event log. A witnessed crime raises it (RecognitionSystem.register_witness);
## it decays passively otherwise (RecognitionSystem warm tick). Rolled against
## on later encounters — recognition is a probability, not a certainty.
@export_range(0.0, 1.0) var recognition_chance: float = 0.0

