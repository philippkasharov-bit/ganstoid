## Data contract for state that exists exactly once in the sim — the player's
## escalation standing. Split out of NPCData (hardening pass): law_tier and
## beef_tiers used to live on every NPC with a doc comment saying "only
## meaningful for the player character" — meaning every civilian, cop, and
## crew member in the city was paying for a Dictionary allocation and two
## fields that only one entity would ever use. Same mistake class as the
## pre-hardening witness-memory log, just on the data-contract side instead
## of the system side.
##
## The player entity is composed as NPCData (shared physical/survival state
## — position, hunger, cash) + this (player-exclusive escalation state), not
## a replacement for NPCData. Any future system that needs "the player"
## finds them via World.get_entities_with_component(ComponentNames.PLAYER_STATE)
## — exactly one match, by construction — rather than a hardcoded id.
class_name PlayerStateData
extends Resource

## Criminal Record Ladder tier (law track). See roadmap Phase 4.
@export var law_tier: GanstoidEnums.LawTier = GanstoidEnums.LawTier.CLEAN

## World.tick of the last escalation (rise, not decay) of law_tier. Required
## to compute the locked "decay pauses and resets on any tier-3+ trigger"
## rule at all — without a timestamp there's nothing to measure the pause
## window against. EscalationTickSystem (Phase 4) is the only writer.
@export var law_tier_last_escalation_tick: int = 0

## Beef Ladder tier (rival gang track), per-faction. faction_id (StringName,
## matches GangData.id) -> GanstoidEnums.BeefTier.
@export var beef_tiers: Dictionary = {}

## Same pause-on-escalation timestamp as law_tier_last_escalation_tick, kept
## per-faction since each gang's beef track decays independently.
## faction_id (StringName) -> int (World.tick).
@export var beef_tier_last_escalation_ticks: Dictionary = {}
