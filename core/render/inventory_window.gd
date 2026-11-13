## UI5/INV2/INV6/INV7: the bag (I), built from Tarkov, DayZ and Zomboid. Left:
## Zomboid's loot side: a column of container buttons (floor, trunk, glovebox,
## each cupboard) and the grid of the one picked, with "Take all". Right: your
## side: weight against what you can carry, the hand slot, the 8x6 bag grid. Every item
## takes its real size. Drag to arrange, drag across to drop or pick up, R to
## turn, double-click to use (or take), right-click for Zomboid-style numbered
## actions, hover for the item card. Game changes go out as requests
## (state.ui_use, state.ui_move) the input system carries out; only the bag
## layout (where a pile sits) is moved here.
class_name InventoryWindow
extends UiWindow

const KIND_COLOURS := {
	"food": Color(0.55, 0.75, 0.35), "drink": Color(0.35, 0.6, 0.85),
	"medical": Color(0.85, 0.35, 0.35), "weapon": Color(0.75, 0.75, 0.72),
	"ammo": Color(0.85, 0.65, 0.3), "goods": Color(0.6, 0.45, 0.75),
}
const VERBS := {"food": "Eat", "drink": "Drink", "medical": "Apply", "weapon": "Equip"}

var _world: World
var _hands := UiTheme.label("", UiTheme.FONT_SMALL)
var _hand_slot := BagGridView.new()
var _hint: Control
var _grid := BagGridView.new()
var _loose := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.BAD)
var _weight_text := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.TEXT)
var _tip := UiTooltip.new()
var _menu := ContextMenu.new()
var _menu_item: StringName = &""
var _key := ""
var _near := BagGridView.new()
var _near_title: Label
var _take_all := Button.new()
var _cont_column := VBoxContainer.new()
var _near_key := ""            # the container picked in the column
var _near_now: Array = []      # what is in it right now
var _weight_bar := Control.new()
var _kg := 0.0
var _menu_src := {}
const NEAR_COLS := 4
const CONT_BTN := Vector2(30, 30)

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("bag", "Bag", at, Vector2(0, 0))
	closed.connect(func() -> void:
		var state := _state()
		if state != null:
			state.inventory_open = false)
	var split := HBoxContainer.new()   # INV4: DayZ layout, vicinity left, your bag right
	split.add_theme_constant_override("separation", 8)
	body.add_child(split)
	split.add_child(_vicinity_pane())
	var mine := VBoxContainer.new()
	mine.add_child(_weight_header())
	var hand_row := HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 8)
	_hand_slot.resize_grid(2, 1)
	_hand_slot.tooltip_text = "In your hand. Drag a weapon here to hold it."
	hand_row.add_child(_hand_slot)
	_hands.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_row.add_child(_hands)
	mine.add_child(hand_row)
	mine.add_child(_grid)
	split.add_child(mine)
	_loose.autowrap_mode = TextServer.AUTOWRAP_WORD
	_loose.custom_minimum_size.x = _grid.custom_minimum_size.x + _near.custom_minimum_size.x
	body.add_child(_loose)
	_hint = UiTheme.key_hints([["RMB", "actions"], ["Dbl-click", "use"], ["R", "rotate"]])   # UI27: one line, the rest is in the right-click menu
	_hint.custom_minimum_size.x = _grid.custom_minimum_size.x + _near.custom_minimum_size.x
	body.add_child(_hint)
	_wire_grid()
	visible = false

func _wire_grid() -> void:
	for popup in [_tip, _menu]:
		add_child(popup)
		popup.top_level = true
	_menu.picked.connect(_on_menu_pick)
	_grid.other = _near
	_grid.hand = _hand_slot
	_grid.moved_to_hand.connect(func(i: int) -> void:
		if ItemCatalog.item(_grid.piles[i]["id"]).get("kind", "") == "weapon":
			_state().ui_use = _grid.piles[i]["id"])
	_near.other = _grid
	_grid.use_pile.connect(func(i: int) -> void: _state().ui_use = _grid.piles[i]["id"])
	_grid.menu_pile.connect(func(i: int, at: Vector2) -> void: _open_menu(_grid.piles[i]["id"], at))
	_grid.moved.connect(func(i: int, cell: Vector2i, turned: bool) -> void: BagGrid.move(_state(), i, cell, turned))
	_grid.moved_out.connect(func(i: int) -> void: _state().ui_move = {"op": "store" if _at_own_place() else "drop", "id": _grid.piles[i]["id"], "n": int(_grid.piles[i]["n"])})
	_near.use_pile.connect(func(i: int) -> void: _take(i, 999))
	_near.moved_out.connect(func(i: int) -> void: _take(i, 999))
	_near.menu_pile.connect(_open_near_menu)
	for view in [_grid, _near]:
		view.hover_pile.connect(func(i: int, at: Vector2) -> void: _show_tip(view.piles[i]["id"], at))
		view.hover_end.connect(_tip.hide_tip)

func _process(_delta: float) -> void:
	var state := _state()
	var now := state != null and state.inventory_open and state.store_id == &""
	visible = now
	if not visible:
		_tip.hide_tip()
		_menu.visible = false
		return
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var near := Vicinity.near(_world, npc, state)
	var key := "%s|%s|%d|%s|%s" % [state.inventory, state.weapon, state.ammo, near, _near_key]
	if key != _key:
		_key = key
		_rebuild(state)
		_show_near(near)

func _rebuild(state: PlayerStateData) -> void:
	BagGrid.sync(state)
	_grid.show_piles(state.bag)
	_hands.text = "%s%s" % [String(state.weapon).capitalize(), "\n%d rounds" % state.ammo if state.ammo > 0 else ""]
	var held := _held_item(state)
	_hand_slot.show_piles([] if held == &"" else [{"id": held, "x": 0, "y": 0, "r": false, "n": 1}])
	var loose := BagGrid.loose(state)
	_loose.visible = not loose.is_empty()
	_loose.text = "No room: " + ", ".join(loose.keys().map(func(id: StringName) -> String: return "%s x%d" % [_name(id), loose[id]]))
	_kg = carried_kg(state)
	_weight_text.text = "%.1f / %.0f kg" % [_kg, ItemCatalog.CARRY_KG]
	_weight_text.add_theme_color_override("font_color", UiTheme.BAD if _kg > ItemCatalog.CARRY_KG else UiTheme.TEXT)
	_weight_bar.queue_redraw()

## Zomboid's weight line over your side: "5.1 / 12 kg" and a bar (red when over).
func _weight_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	var name_label := UiTheme.label("Your bag", UiTheme.FONT_SMALL, UiTheme.DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_weight_text)
	box.add_child(row)
	_weight_bar.custom_minimum_size = Vector2(0, 4)
	_weight_bar.draw.connect(func() -> void:
		var f := _kg / ItemCatalog.CARRY_KG
		_weight_bar.draw_rect(Rect2(Vector2.ZERO, _weight_bar.size), Color(1, 1, 1, 0.08))
		_weight_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(_weight_bar.size.x * minf(f, 1.0), 4)), UiTheme.BAD if f > 1.0 else UiTheme.ACCENT))
	box.add_child(_weight_bar)
	return box

## The item that matches the weapon in hand (pistol in hand -> the pistol item).
static func _held_item(state: PlayerStateData) -> StringName:
	for id in state.inventory:
		if ItemCatalog.item(id).get("weapon", &"") == state.weapon:
			return id
	return &""

static func carried_kg(state: PlayerStateData) -> float:
	var kg := 0.0
	for id in state.inventory:
		kg += ItemCatalog.item(id).get("weight", 0.0) * state.inventory[id]
	return kg

static func _name(id: StringName) -> String:
	return ItemCatalog.item(id).get("name", String(id).capitalize())

## Zomboid-style right-click: the obvious action first, numbered, greyed with a reason.
func _open_menu(id: StringName, at: Vector2) -> void:
	_menu_item = id
	_tip.hide_tip()
	var kind: String = ItemCatalog.item(id).get("kind", "goods")
	var options: Array = [{"text": VERBS.get(kind, "Use"), "enabled": VERBS.has(kind), "why": "sell it to a dealer" if kind == "goods" else "loads into your gun"}]
	var count := int(_state().inventory.get(id, 0))
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var car := VehicleSystem.nearest_car(_world, npc.position)
	var trunk_ok := car != null and (car.owner_id == PlayerFactory.PLAYER_ENTITY_ID or not car.locked)
	options.append({"text": "Inspect", "enabled": true})
	options.append({"text": "Drop one", "enabled": true})
	options.append({"text": "Drop all (%d)" % count, "enabled": count > 1, "why": "only one"})
	options.append({"text": "Put in trunk", "enabled": trunk_ok, "why": "no open car here"})
	_menu_src = {}
	_menu.open_at(at, options)

func _on_menu_pick(index: int) -> void:
	if _menu_item == &"":
		return
	var st := _state()
	if not _menu_src.is_empty():   # a vicinity row: take one / take all
		st.ui_move = {"op": "take", "src": _menu_src, "n": 1 if index == 0 else 999}
		return
	var count := int(st.inventory.get(_menu_item, 0))
	match index:
		0: st.ui_use = _menu_item
		1: _show_tip(_menu_item, get_global_mouse_position())
		2: st.ui_move = {"op": "drop", "id": _menu_item, "n": 1}
		3: st.ui_move = {"op": "drop", "id": _menu_item, "n": count}
		4: st.ui_move = {"op": "stash", "id": _menu_item, "n": count}

func _show_tip(id: StringName, at: Vector2) -> void:
	var it := ItemCatalog.item(id)
	if id == &"cash":
		_tip.show_at(at, "Cash", [["Money, not a bag item", UiTheme.GOOD]], "Take it and it goes in your pocket (dirty).")
		return
	if it.is_empty():
		_tip.show_at(at, _name(id), [["Street goods", KIND_COLOURS["goods"]]], "Sell it to a dealer.")
		return
	_tip.show_at(at, it["name"], ItemCard.lines(id))

## INV6/INV7: the loot side: container buttons, then the picked one's grid.
func _vicinity_pane() -> HBoxContainer:
	var pane := HBoxContainer.new()
	pane.add_theme_constant_override("separation", UiTheme.GAP)
	_cont_column.add_theme_constant_override("separation", UiTheme.GAP)
	_cont_column.custom_minimum_size.x = CONT_BTN.x
	pane.add_child(_cont_column)
	var right := VBoxContainer.new()
	var head := HBoxContainer.new()
	_near_title = UiTheme.label("Nearby", UiTheme.FONT_SMALL, UiTheme.DIM)
	_near_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_near_title)
	_take_all.text = "Take all"
	_take_all.focus_mode = Control.FOCUS_NONE
	_take_all.add_theme_font_size_override("font_size", 10)
	for look in ["normal", "hover", "pressed", "disabled"]:
		_take_all.add_theme_stylebox_override(look, UiTheme.button_box(look))
	_take_all.pressed.connect(func() -> void: _state().ui_move = {"op": "take_all", "srcs": _near_now})
	head.add_child(_take_all)
	right.add_child(head)
	_near.resize_grid(NEAR_COLS, BagGrid.ROWS)
	right.add_child(_near)
	pane.add_child(right)
	return pane

## Fills the column (one button per container) and the grid of the picked one.
func _show_near(near: Array) -> void:
	var keys := Vicinity.sources(near)
	if not keys.has(_near_key):
		_near_key = keys[0] if not keys.is_empty() else ""
	for c in _cont_column.get_children():
		_cont_column.remove_child(c)
		c.queue_free()
	for k in keys:
		_cont_column.add_child(_cont_button(k, k == _near_key))
	_near_now = Vicinity.only(near, _near_key)
	_near.show_piles(Vicinity.layout(_near_now, NEAR_COLS, BagGrid.ROWS))
	_near_title.text = Vicinity.title_of(_near_key) if _near_key != "" else "Nothing in reach"
	_take_all.disabled = _near_now.is_empty()

const CONT_ICONS := {"ground": "floor", "trunk": "trunk", "glovebox": "glovebox"}

func _cont_button(key: String, on: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CONT_BTN
	b.tooltip_text = Vicinity.title_of(key)
	for look in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(look, UiTheme.button_box("on" if on else look))
	var icon: String = CONT_ICONS.get(key, "stash" if key == "container:" + Containers.STASH else "drawer")
	var art := Moodles.icon_or_glyph(icon, Vicinity.title_of(key).left(1), 20)
	art.position = (CONT_BTN - Vector2(20, 20)) * 0.5
	art.modulate = UiTheme.TEXT if on else UiTheme.DIM
	b.add_child(art)
	b.pressed.connect(func() -> void:
		_near_key = key
		_key = "")
	return b

## LT1: inside your own place, what you drag out of the bag goes in your stash.
func _at_own_place() -> bool:
	var st := _state()
	var e: Entity = _world.entities.get(st.inside_id) if st.inside_id != &"" else null
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	return e != null and Containers.is_yours(npc, e.get_component(ComponentNames.BUILDING))

func _take(i: int, n: int) -> void:
	_state().ui_move = {"op": "take", "src": _near.piles[i]["src"], "n": n}

func _open_near_menu(i: int, at: Vector2) -> void:
	_menu_item = _near.piles[i]["id"]
	_menu_src = _near.piles[i]["src"]
	_tip.hide_tip()
	_menu.open_at(at, [{"text": "Take one"}, {"text": "Take all (%d)" % int(_near.piles[i]["n"])}])

func _state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
