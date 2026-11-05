## Thin scene-tree adapter: the only piece of the ECS layer that touches
## Godot's process loop. Intended as an autoload singleton — everything else
## in core/ecs stays engine-agnostic and testable without this node.
extends Node

var world: World = World.new()

func _physics_process(delta: float) -> void:
	world.step(delta)
