## Thin scene-tree adapter: the only piece of the SIMULATION layer that
## touches Godot's process loop — everything else in core/ecs stays
## engine-agnostic and testable without this node. (core/render/render_sync.gd
## is its sibling on the rendering side, reading World through this node's
## `world` property; it's a separate concern, not a reason to route
## rendering through here too.)
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
## Bumped for the "Sprawl (LA-ish)" layout (CityGenerator) -- the irregular
## boundary crops some of the square grid away, and two offset commercial
## hubs plus a major/minor street hierarchy need enough lots to read
## clearly rather than looking cramped.
const DEV_GRID_WIDTH := 26
const DEV_GRID_HEIGHT := 26
const DEV_POPULATION_COUNT := 130

var world: World = World.new()

func _ready() -> void:
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, DEV_WORLD_SEED, DEV_GRID_WIDTH, DEV_GRID_HEIGHT, DEV_POPULATION_COUNT)

func _physics_process(delta: float) -> void:
	world.step(delta)
