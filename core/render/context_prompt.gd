## UI4: what you can do right here, shown over the thing you can do it to: a
## small pill with the key ("E  Talk · Pickpocket", "E  Search their pockets",
## "E  Break in", "F  Get in"), so you never open a menu just to find out.
## The nearest thing wins: someone down, a fixer or dealer, a person, a shop
## counter, a front door, a car. Hidden while a menu or window has the keys.
## Read-only.
class_name ContextPrompt
extends Control

const REFRESH_S := 0.15
const LIFT_PX := 46.0

var _world: World
var _left := 0.0
var _at := Vector2.INF        # map point of the thing
var _key := ""
var _text := ""

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_S
		_pick()
	queue_redraw()

func _pick() -> void:
	_at = Vector2.INF
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null or GameRules.of(_world) == null:
		return
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	if me.is_down or state.sleeping or not state.menu_options.is_empty() or state.store_id != &"" or state.inventory_open or not state.lift.is_empty() or state.vehicle_id != &"":
		return
	var found := what_here(_world, me)
	if not found.is_empty():
		_at = found["at"]
		_key = found["key"]
		_text = found["text"]

## The thing to do nearest you: {at, key, text}, or {}.
static func what_here(world: World, me: NPCData) -> Dictionary:
	var reach := CrimeSystem.INTERACT_RADIUS
	var best := {}
	var best_rank := 99
	var best_d := INF
	for id in world.spatial_index.query_nearby(me.position):
		var e: Entity = world.entities.get(id)
		if e == null or id == PlayerFactory.PLAYER_ENTITY_ID:
			continue
		var n: NPCData = e.get_component(ComponentNames.NPC)
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		var at := Vector2.INF
		var rank := 99
		var text := ""
		if n != null and not n.indoors and not n.is_crew:
			at = n.position
			if n.is_down:
				rank = 0
				text = "Search their pockets"
			elif n.is_fixer:
				rank = 1
				text = "Ask for work"
			elif n.is_dealer:
				rank = 1
				text = "Buy · Sell"
			elif n.is_cop:
				rank = 3
				text = "Talk · Bribe"
			else:
				rank = 2
				text = "Talk · Pickpocket · more"
		elif b != null:
			at = b.position
			if ShopSystem.counter_kind(world, id) != "":
				rank = 3
				text = "Shop" if ShopSystem.is_open(world, id) else "Closed"
			elif b.building_type == GanstoidEnums.BuildingType.RESIDENCE and b.id != me.home_building_id:
				rank = 4
				text = "Break in"
		if rank == 99:
			continue
		var d := at.distance_to(me.position)
		if d <= reach and (rank < best_rank or (rank == best_rank and d < best_d)):
			best = {"at": at, "key": "E", "text": text}
			best_rank = rank
			best_d = d
	if best.is_empty():
		var car := VehicleSystem.nearest_car(world, me.position)
		if car != null:
			var open: bool = car.owner_id == PlayerFactory.PLAYER_ENTITY_ID or not car.locked
			best = {"at": car.position, "key": "F" if open else "E", "text": "Get in" if open else "Locked car: Car menu"}
	return best

func _draw() -> void:
	if _at == Vector2.INF:
		return
	var s := ScreenMap.to_screen(get_viewport(), _at, 2.0) + Vector2(0, -LIFT_PX)
	var font := get_theme_default_font()
	var kf := UiTheme.font("bungee")
	var tw := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var w := 22.0 + 8.0 + tw + 10.0
	var box := Rect2(s - Vector2(w * 0.5, 12), Vector2(w, 24))
	draw_rect(box, Color(0.04, 0.04, 0.05, 0.82))
	draw_rect(box, Color(1, 1, 1, 0.12), false, 1.0)
	var key := Rect2(box.position + Vector2(4, 3), Vector2(22, 18))
	draw_rect(key, UiTheme.ACCENT)
	draw_string(kf, key.position + Vector2(6, 15), _key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.08, 0.07, 0.05))
	draw_string(font, box.position + Vector2(32, 17), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
