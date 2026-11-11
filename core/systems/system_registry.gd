## Single place every active system gets wired into a World. Keeps
## world_driver.gd from growing a system list as more systems get added
## across later phases — this file is the one place to see what's running.
##
## World itself owns the cross-cutting infrastructure systems don't need to
## be registered to use: spatial_index (proximity queries) and event_bus
## (cross-system notifications) are already live on every World instance —
## see core/ecs/world.gd.
##
## This is also the one place EventBus listeners get wired up. A system
## that needs to react to an event (not just run every tick) still gets
## registered normally AND has its handler subscribed here, right next to
## its registration -- so "what listens to crime_witnessed" is answered by
## reading this one function, not by grepping for event_bus.subscribe calls
## scattered across the codebase.
class_name SystemRegistry
extends RefCounted

static func register_all(world: World) -> void:
	world.register_system(RecognitionSystem.new())
	var schedule := NPCScheduleSystem.new(world)
	world.register_system(schedule)
	world.event_bus.subscribe(schedule.on_gunshot)
	world.register_system(PlayerInputSystem.new(world))
	world.register_system(NeedsSystem.new(world))
	world.register_system(WitnessCallSystem.new(world))
	world.register_system(RankSystem.new(world))
	world.register_system(JobSystem.new(world))
	world.register_system(TrafficSystem.new(world))
	var case := CaseSystem.new(world)
	world.register_system(case)
	world.event_bus.subscribe(case.on_crime_witnessed)
	var turf := TerritorySystem.new(world)
	world.register_system(turf)
	world.event_bus.subscribe(turf.on_assaulted)
	var wounds := WoundSystem.new(world)
	world.register_system(wounds)
	world.event_bus.subscribe(wounds.on_wounded)
	world.register_system(CrewSystem.new(world))
	world.register_system(CrewLoyaltySystem.new(world))
	world.register_system(CrewDealerSystem.new(world))
	world.register_system(CrewMuscleSystem.new(world))
	world.register_system(CrewBustSystem.new(world))
	world.register_system(BusinessSystem.new(world))
	world.register_system(ProductionSystem.new(world))
	world.register_system(EconomySystem.new(world))

	var npc_combat := NPCCombatSystem.new(world)
	world.register_system(npc_combat)
	world.event_bus.subscribe(npc_combat.on_assaulted)

	var cop_ai := CopAISystem.new(world)
	world.register_system(cop_ai)
	world.event_bus.subscribe(cop_ai.on_crime_witnessed)

	var escalation := EscalationTickSystem.new(world)
	world.register_system(escalation)
	world.event_bus.subscribe(escalation.on_crime_witnessed)
