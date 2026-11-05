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
## Tiers 1-3 decay normally while player stays at/below tier-2 activity.
## Tier 4 (CONTRACT) never passively decays — only clears via gang destruction
## (GangData.is_destroyed). Never auto-decay CONTRACT in the heat system.
enum BeefTier {
	NONE,
	WARNED,
	RETALIATING,
	HUNTED,           # tier 3: active hunting, informants planted
	CONTRACT,         # tier 4: permanent assassination contract
}

## ECS system update frequency (core/ecs/world.gd). Hot = every tick,
## warm = periodic batch, cold = on-demand/event-triggered only.
enum TickRate {
	HOT,
	WARM,
	COLD,
}
