## Local witness layer: each NPC independently might-or-might-not recognize
## the player on sight. Feeds the GLOBAL LawTier/BeefTier ladders (enums.gd)
## probabilistically — a successful roll_recognized() is what Phase 1's crime
## system uses to decide whether a witnessed act actually escalates those
## tiers, rather than every witness guaranteeing escalation.
##
## Deliberately a single scalar per NPC, not an event log: O(1) per NPC per
## tick regardless of city size, and closer to how memory actually works —
## people don't keep a dated list of your crimes, they have a fading hunch.
class_name RecognitionSystem
extends SystemBase

## Multiplicative decay per warm tick (~10 sim ticks). 0.98 gives a fast
## initial drop-off with a long tail, matching real forgetting curves better
## than a linear decay would.
const DECAY_FACTOR_PER_WARM_TICK := 0.98

## Below this, treat as fully forgotten — avoids an infinite asymptotic tail
## of float dust that never quite reaches zero.
const FORGOTTEN_THRESHOLD := 0.01

func _init() -> void:
	tick_rate = GanstoidEnums.TickRate.WARM
	# World hands this system only NPCData-bearing entities (its index),
	# not a scan of every building and gang in the city too.
	required_component = ComponentNames.NPC

## Also iterates the player's own entity (they carry NPCData too, for
## shared physical state) -- harmless, not a bug: recognition_chance means
## nothing for the player and nothing ever raises theirs above 0.0, so they
## hit the early-exit below every tick at negligible cost. Not worth a
## second marker component to exclude one always-zero entity from a loop.
func process_entities(entities: Dictionary, _delta: float, _tick: int) -> void:
	for entity in entities.values():
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc.recognition_chance <= 0.0:
			continue
		npc.recognition_chance *= DECAY_FACTOR_PER_WARM_TICK
		if npc.recognition_chance < FORGOTTEN_THRESHOLD:
			npc.recognition_chance = 0.0

## Called by the crime/witness trigger (Phase 1) when this NPC sees something.
## Approaches 1.0 with diminishing returns — a civilian already fairly sure
## doesn't gain much from seeing one more thing; a clean slate jumps hard.
static func register_witness(npc: NPCData, severity: float) -> void:
	var clamped_severity := clampf(severity, 0.0, 1.0)
	npc.recognition_chance += (1.0 - npc.recognition_chance) * clamped_severity

## Called on player-NPC encounter (Phase 1) to roll whether this NPC clocks
## the player. A pure probability check — recognition is never guaranteed.
static func roll_recognized(npc: NPCData, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < npc.recognition_chance
