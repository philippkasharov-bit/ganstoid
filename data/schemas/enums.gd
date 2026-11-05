## Shared enums referenced across data contracts.
## Centralized so tier/type IDs stay stable as save data accumulates —
## never reorder existing entries, only append.
class_name GanstoidEnums

enum BuildingType {
	RESIDENCE,
	LEGIT_BUSINESS,
	ILLEGAL_FRONT,
	SAFEHOUSE,
}

enum CrewRole {
	MUSCLE,
	LOOKOUT,
	FENCE,
	DEALER,
	DRIVER,
}

## Criminal Record Ladder tiers (law track). See roadmap Phase 4.
## Tier 0 = clean. Floor only rises via CRIME_WITNESSED/CRIME_VIOLENT events;
## decays per-tier at runtime, tier 3 decays far slower than 1-2.
enum LawTier {
	CLEAN,
	WARNED,          # tier 1: warning / short jail
	REPEAT_OFFENDER,  # tier 2: longer jail, assets seized
	INVESTIGATED,     # tier 3: proactive investigation
	SHOOT_FIRST,      # tier 4: cops skip non-lethal, draw faster (not kill-on-sight)
}

## Beef Ladder tiers (rival gang track), per-faction. See roadmap Phase 4.
## Tier 3 (HUNTED) is a permanent flag that only clears via gang destruction —
## never auto-decay this tier in the economy/heat system.
enum BeefTier {
	NONE,
	WARNED,
	RETALIATING,
	HUNTED,           # tier 3: active hunting, informants planted
	CONTRACT,         # tier 4: permanent assassination contract
}
