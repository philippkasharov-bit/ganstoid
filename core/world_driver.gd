## Thin scene-tree adapter: the only piece of the ECS layer that touches
## Godot's process loop. Intended as an autoload singleton — everything else
## in core/ecs stays engine-agnostic and testable without this node.
##
## Simulation-fidelity LOD (deferred, not Phase 0): the plan is that systems
## far from the player eventually run at reduced fidelity (longer effective
## tick interval, or skip non-essential fields) rather than full detail for
## every NPC in the whole city at once — the same cost problem that already
## ruled out live-LLM NPCs, just at the rule-based-sim layer instead. This is
## a Ganstoid design choice, NOT a confirmed fact about how Zomboid's engine
## works internally (its cell-based *map streaming* is well documented; its
## simulation-detail behavior for distant cells isn't, in anything findable).
## SpatialIndex (core/ecs/spatial_index.gd) is the piece this will build on —
## cell membership is already computed, so "which systems run at what
## fidelity for this cell" is a Phase 1+ addition on top, not a rearchitect.
extends Node

var world: World = World.new()

func _ready() -> void:
	SystemRegistry.register_all(world)

func _physics_process(delta: float) -> void:
	world.step(delta)
