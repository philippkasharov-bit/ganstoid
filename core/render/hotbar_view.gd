## HB1: the hotbar at the bottom middle of the screen, Zomboid's: a row of
## square slots, each with its key number, the item drawn in it and its count
## (rounds for the gun). The weapon in your hand has the gold frame. Click a
## slot to do what its key does. Hidden while a window covers the play.
class_name HotbarView
extends Control

const SLOT := 44.0
const GAP := 4.0
const REFRESH_S := 0.2

var _world: World
var _slots: Array = []
var _state: PlayerStateData
var _left := 0.0
var _hovered := -1
var _tip := UiTooltip.new()
var _press_i := -1        # A6: the slot just used presses in
var _press_t := 9.0
var _weapon: StringName = &""   # A8: the weapon in hand last frame
var _swap_t := 9.0
const PRESS_S := 0.18
const POP_S := 0.3

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tip)
	_tip.top_level = true
	visible = false

func _process(delta: float) -> void:
	_press_t += delta
	_swap_t += delta
	_watch_keys()
	if _press_t < PRESS_S or _swap_t < POP_S:
		queue_redraw()
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = REFRESH_S
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	_state = p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
	visible = _state != null and GameRules.of(_world) != null and _state.vehicle_id == &"" and _state.prison_until_tick <= 0
	if not visible:
		_tip.hide_tip()
		return
	_slots = Hotbar.slots(_state)
	var n := maxi(1, _slots.size())
	size = Vector2(n * SLOT + (n - 1) * GAP, SLOT)
	var screen := get_viewport_rect().size
	position = Vector2(roundf((screen.x - size.x) * 0.5), screen.y - SLOT - UiTheme.MARGIN)
	queue_redraw()

## A6/A8: notices a slot key, and a weapon change, the moment they happen.
func _watch_keys() -> void:
	if _state == null or not visible:
		return
	if _state.menu_options.is_empty() and _state.store_id == &"" and not _state.inventory_open:
		for k in mini(_slots.size(), PlayerInputSystem.SLOT_ACTIONS.size()):
			if Input.is_action_just_pressed(PlayerInputSystem.SLOT_ACTIONS[k]):
				_press_i = k
				_press_t = 0.0
	if _state.weapon != _weapon:
		if _weapon != &"":
			_swap_t = 0.0
		_weapon = _state.weapon

func _rect(i: int) -> Rect2:
	return Rect2(Vector2(i * (SLOT + GAP), 0), Vector2(SLOT, SLOT))

func _draw() -> void:
	if _state == null:
		return
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var r := _rect(i)
		if i == _press_i and _press_t < PRESS_S:   # A6: pressed in, then back
			r = r.grow(-3.0 * sin(PI * _press_t / PRESS_S))
		var held := Hotbar.in_hand(_state, s)
		if held and _swap_t < POP_S:   # A8: the new weapon's frame pops
			draw_rect(r.grow(6.0 * (1.0 - _swap_t / POP_S)), Color(UiTheme.ACCENT, 1.0 - _swap_t / POP_S), false, 2.0)
		draw_rect(r, UiTheme.BG)
		draw_rect(r, UiTheme.ACCENT if held else (Color(1, 1, 1, 0.3) if i == _hovered else Color(1, 1, 1, 0.12)), false, 2.0 if held else 1.0)
		var kind: String = ItemCatalog.item(s["id"]).get("kind", "goods")
		ItemArt.draw(self, s["id"], r.grow(-8), InventoryWindow.KIND_COLOURS.get(kind, UiTheme.DIM), false)
		var font := ThemeDB.fallback_font
		draw_string(font, r.position + Vector2(4, 11), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.ACCENT)
		var count := _count(s)
		if count != "":
			draw_string(font, r.position + Vector2(0, SLOT - 3), count, HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 4, 10, UiTheme.TEXT)

## Rounds for the gun, how many for the rest (blank for one).
func _count(s: Dictionary) -> String:
	if ItemCatalog.item(s["id"]).get("weapon", &"") == &"pistol":
		return str(_state.ammo)
	var n := int(_state.inventory.get(s["id"], 0))
	return str(n) if n > 1 else ""

func _gui_input(event: InputEvent) -> void:
	var hit := -1
	if event is InputEventMouse:
		for i in _slots.size():
			if _rect(i).has_point(event.position):
				hit = i
	if event is InputEventMouseMotion and hit != _hovered:
		_hovered = hit
		queue_redraw()
		if hit >= 0:
			var it := ItemCatalog.item(_slots[hit]["id"])
			var verb: String = "Put away" if Hotbar.in_hand(_state, _slots[hit]) else ("Hold" if it["kind"] == "weapon" else InventoryWindow.VERBS.get(it["kind"], "Use"))
			var card := ItemCard.lines(_slots[hit]["id"], _state)
			card.append(["%s  [%d]" % [verb, hit + 1], UiTheme.ACCENT])
			_tip.show_at(global_position + _rect(hit).position - Vector2(0, 150), it["name"], card)
		else:
			_tip.hide_tip()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hit >= 0:
		_state.ui_hotbar = hit
		_press_i = hit
		_press_t = 0.0
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hovered = -1
		_tip.hide_tip()
		queue_redraw()
