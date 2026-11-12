## UI5/INV2: the bag (I), built from Tarkov, DayZ and Zomboid: what is in your
## hands on top, the 8x6 grid where every item takes its real size, anything
## that found no room listed as loose, weight at the bottom. Drag to arrange,
## R to turn, double-click or 1-9 to use, right-click for Zomboid-style
## numbered actions, hover for the item card. Reads state; the one write is
## state.ui_use, a request the input system carries out on its next tick.
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
var _grid := BagGridView.new()
var _loose := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.BAD)
var _weight_text := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DIM)
var _tip := UiTooltip.new()
var _menu := ContextMenu.new()
var _menu_item: StringName = &""
var _key := ""
var _near := VBoxContainer.new()
var _near_src: Array = []
var _menu_src := {}

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("bag", "Bag", at, Vector2(0, 0))
	closed.connect(func() -> void:
		var state := _state()
		if state != null:
			state.inventory_open = false)
	_hands.add_theme_font_override("font", UiTheme.font("marker"))
	var split := HBoxContainer.new()   # INV4: DayZ layout, vicinity left, your bag right
	split.add_theme_constant_override("separation", 8)
	body.add_child(split)
	split.add_child(_vicinity_pane())
	var mine := VBoxContainer.new()
	mine.add_child(_hands)
	mine.add_child(_grid)
	split.add_child(mine)
	_loose.autowrap_mode = TextServer.AUTOWRAP_WORD
	_loose.custom_minimum_size.x = _grid.custom_minimum_size.x
	body.add_child(_loose)
	body.add_child(_weight_text)
	body.add_child(UiTheme.label("Drag · R turn · double-click use · right-click", 10, UiTheme.DIM))
	_wire_grid()
	visible = false

func _wire_grid() -> void:
	for popup in [_tip, _menu]:
		add_child(popup)
		popup.top_level = true
	_menu.picked.connect(_on_menu_pick)
	_grid.use_item.connect(func(id: StringName) -> void: _state().ui_use = id)
	_grid.menu_item.connect(_open_menu)
	_grid.hover_item.connect(func(id: StringName, at: Vector2) -> void: _show_tip(id, at))
	_grid.hover_end.connect(_tip.hide_tip)

func _process(_delta: float) -> void:
	var state := _state()
	visible = state != null and state.inventory_open and state.store_id == &""
	if not visible:
		_tip.hide_tip()
		_menu.visible = false
		return
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var near := Vicinity.near(_world, npc, state)
	var key := "%s|%s|%d|%s" % [state.inventory, state.weapon, state.ammo, near]
	if key != _key:
		_key = key
		_rebuild(state)

		_rebuild_near(near)

func _rebuild(state: PlayerStateData) -> void:
	BagGrid.sync(state)
	_grid.state = state
	_grid.queue_redraw()
	_hands.text = "In hand:  %s%s" % [String(state.weapon).capitalize(), "   ·   %d rounds" % state.ammo if state.ammo > 0 else ""]
	var loose := BagGrid.loose(state)
	_loose.visible = not loose.is_empty()
	_loose.text = "No room: " + ", ".join(loose.keys().map(func(id: StringName) -> String: return "%s x%d" % [_name(id), loose[id]]))
	var kg := carried_kg(state)
	_weight_text.text = "%.1f kg   ·   %d of %d cells used" % [kg, BagGrid.occupancy(state.bag).size(), BagGrid.COLS * BagGrid.ROWS]

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
	if it.is_empty():
		_tip.show_at(at, _name(id), [["Street goods", KIND_COLOURS["goods"]]], "Sell it to a dealer.")
		return
	var lines: Array = [[String(it["kind"]).capitalize(), KIND_COLOURS.get(it["kind"], UiTheme.TEXT)]]
	for stat in ["hunger", "thirst", "tired", "heal"]:
		if it.has(stat):
			lines.append(["%s +%d%%" % [{"hunger": "Food", "thirst": "Water", "tired": "Energy", "heal": "Health"}[stat], roundi(it[stat] * 100)], UiTheme.GOOD])
	if it.has("weapon"):
		lines.append(["Damage %d" % roundi(CombatSystem.WEAPONS[it["weapon"]].get("damage", 0.0) * 100), UiTheme.TEXT])
	if it.has("rounds"):
		lines.append(["%d rounds" % it["rounds"], UiTheme.TEXT])
	var f := ItemCatalog.size_of(id)
	lines.append(["%dx%d cells   ·   %.1f kg   ·   $%d" % [f.x, f.y, it.get("weight", 0.0), it["price"]], UiTheme.DIM])
	_tip.show_at(at, it["name"], lines)

## INV4: the vicinity column (DayZ): what is on the ground or in the trunk
## next to you. Double-click takes it all, right-click for one or all.
func _vicinity_pane() -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.custom_minimum_size = Vector2(120, 0)
	var title := UiTheme.label("Nearby", UiTheme.FONT_SMALL, UiTheme.DIM)
	title.add_theme_font_override("font", UiTheme.font("marker"))
	pane.add_child(title)
	_near.add_theme_constant_override("separation", 1)
	pane.add_child(_near)
	return pane

func _rebuild_near(near: Array) -> void:
	_near_src = near
	for c in _near.get_children():
		_near.remove_child(c)
		c.queue_free()
	if near.is_empty():
		_near.add_child(UiTheme.label("Nothing here.", UiTheme.FONT_SMALL, UiTheme.DIM))
	for src in near:
		_near.add_child(_near_row(src))

func _near_row(src: Dictionary) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s%s x%d" % ["" if src["kind"] == "ground" else "TRUNK  ", BagGridView._short(src["id"]), src["n"]]
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	var kind: String = ItemCatalog.item(src["id"]).get("kind", "goods")
	b.add_theme_color_override("font_color", KIND_COLOURS.get(kind, UiTheme.TEXT))
	b.tooltip_text = "%s (%s). Double-click: take all." % [_name(src["id"]), "on the ground" if src["kind"] == "ground" else "in the trunk"]
	b.gui_input.connect(func(e: InputEvent) -> void: _on_near_input(e, src))
	return b

func _on_near_input(e: InputEvent, src: Dictionary) -> void:
	if not e is InputEventMouseButton or not e.pressed:
		return
	if e.button_index == MOUSE_BUTTON_LEFT and e.double_click:
		_state().ui_move = {"op": "take", "src": src, "n": 999}
	elif e.button_index == MOUSE_BUTTON_RIGHT:
		_menu_item = src["id"]
		_menu_src = src
		_menu.open_at(get_global_mouse_position(), [{"text": "Take one"}, {"text": "Take all (%d)" % src["n"]}])

func _state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
