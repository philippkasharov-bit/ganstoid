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

## Dev-default new-game parameters -- hardcoded so Phase 0's architecture
## has something real to run end to end instead of booting to an empty
## World with zero entities. Nothing in core/ depends on these specific
## values; replace this with an actual new-game/save-load/menu flow once
## Phase 1+ needs one.
const DEV_WORLD_SEED := 1
const DEV_GRID_WIDTH := 10
const DEV_GRID_HEIGHT := 10
const DEV_POPULATION_COUNT := 50

var world: World = World.new()

func _ready() -> void:
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, DEV_WORLD_SEED, DEV_GRID_WIDTH, DEV_GRID_HEIGHT, DEV_POPULATION_COUNT)

func _physics_process(delta: float) -> void:
	world.step(delta)
