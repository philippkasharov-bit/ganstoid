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
	UNASSIGNED,  # batch 15: freshly recruited, no task yet (appended last so existing values keep their numbers)
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

## City zone of a building (CityRoles). Computed once at new-game start from
## where the building stands (commercial area, industrial area / dark spots) and stored on
## BuildingData.zone — later systems (cop patrol density, pricing, where
## crews recruit) read the stored zone rather than recomputing geometry.
## DOWNTOWN = small dense business core. SPRAWL = wide residential spread
## (the bulk of the map). EDGE = rougher outskirts where illegal fronts and
## safehouses cluster.
enum CityZone {
	DOWNTOWN,
	SPRAWL,
	EDGE,
}

## Crime types (Phase 1 locked mechanics spec). Each has a fixed witness
## severity (CrimeSystem.SEVERITY_BY_TYPE) regardless of whether it has a
## gameplay EFFECT implemented yet — PICKPOCKET is the only one with a real
## effect (cash transfer) this phase; the rest can still be witnessed/escalate
## heat once wired in, without CrimeSystem needing a reshape to add them.
enum CrimeType {
	PICKPOCKET,
	CAR_BREAK_IN,
	DRUG_DEAL_OBSERVED,
	ASSAULT,
	ARMED_ROBBERY,
	MURDER,
	## Batch 9 (locked): witnessed act of doing a paid job on a gang's own
	## turf (CrimeSystem.do_gang_job) -- riskier than a quiet drug deal
	## (you're visibly working a corner) but nowhere near as alarming as an
	## armed robbery, so its severity sits between the two.
	GANG_JOB,
	## Batch 19: crew muscle leaning on a shop for protection money.
	EXTORTION,
	## X2: breaking into a house.
	BURGLARY,
}
