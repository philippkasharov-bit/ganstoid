## Thin scene-tree adapter: the only piece of the SIMULATION layer that
## touches Godot's process loop — everything else in core/ecs stays
## engine-agnostic and testable without this node. (core/render/render_sync.gd
## is its sibling on the rendering side, reading World through this node's
## `world` property.)
##
## MG1c: every new game runs on the REAL city (fixed LA map). A fresh seed per
## run reshuffles building roles and people; the map itself never changes.
## Street routes for the district sync in the background (Godot 4.7, ~2 s): the
## HUD shows a loading line and the sim waits until they are ready.
extends Node

const DISTRICT_RADIUS := 900.0   # metres around the spawn that are simulated
const DEV_POPULATION_COUNT := 130

var world: World = World.new()
var city: CityData
var seed_used := 0

func _ready() -> void:
	city = CityData.load_file()
	seed_used = randi()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_real_city_game(world, seed_used, city, city.spawn, DISTRICT_RADIUS, DEV_POPULATION_COUNT)
	_install_routes.call_deferred()

func _install_routes() -> void:
	await get_tree().process_frame   # let the loading line render first
	await get_tree().process_frame
	SimNav.install(city, city.spawn, DISTRICT_RADIUS)

func _physics_process(delta: float) -> void:
	if SimNav.active == null or not SimNav.active.is_ready():
		return   # routes still loading: nobody moves yet
	world.step(delta)

func _exit_tree() -> void:
	SimNav.uninstall()
