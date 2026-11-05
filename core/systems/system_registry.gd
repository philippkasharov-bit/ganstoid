## Single place every active system gets wired into a World. Keeps
## world_driver.gd from growing a system list as more systems get added
## across later phases — this file is the one place to see what's running.
##
## World itself owns the cross-cutting infrastructure systems don't need to
## be registered to use: spatial_index (proximity queries) and event_bus
## (cross-system notifications) are already live on every World instance —
## see core/ecs/world.gd.
class_name SystemRegistry
extends RefCounted

static func register_all(world: World) -> void:
	world.register_system(RecognitionSystem.new())
