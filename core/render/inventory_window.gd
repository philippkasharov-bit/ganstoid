## UI5: the bag (I), Zomboid-style: a movable window with what you carry on
## the left (hands slot, numbered lines, weight bar) and who you are on the
## right. Click or 1-9 uses a line, right-click opens its menu, hover shows
## the item card. Reads state; the one write is state.ui_use, a request the
## input system carries out on its next tick.
class_name InventoryWindow
extends UiWindow

const KIND_COLOURS := {
	"food": Color(0.55, 0.75, 0.35), "drink": Color(0.35, 0.6, 0.85),
	"medical": Color(0.85, 0.35, 0.35), "weapon": Color(0.75, 0.75, 0.72),
	"ammo": Color(0.85, 0.65, 0.3), "goods": Color(0.6, 0.45, 0.75),
}
const VERBS := {"food": "Eat", "drink": "Drink", "medical": "Apply", "weapon": "Hold"}

var _world: World
var _hands := UiTheme.label("")
var _lines := VBoxContainer.new()
var _weight_bar := ProgressBar.new()
var _weight_text := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DIM)
var _about := VBoxContainer.new()
var _tip := UiTooltip.new()
var _menu := ContextMenu.new()
var _menu_item: StringName = &""
var _key := ""

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("bag", "Bag", at, Vector2(560, 320))
	closed.connect(func() -> void:
		var state := _state()
		if state != null:
			state.inventory_open = false)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	body.add_child(split)
	split.add_child(_you_pane())
	split.add_child(VSeparator.new())
	_about.custom_minimum_size.x = 200
	_about.add_theme_constant_override("separation", 3)
	split.add_child(_about)
	add_child(_tip)
	_tip.top_level = true
	add_child(_menu)
	_menu.top_level = true
	_menu.picked.connect(_on_menu_pick)
	body.add_child(UiTheme.label("Click or 1-9 use    Right-click more    I / Esc close", UiTheme.FONT_SMALL, UiTheme.DIM))
	visible = false

func _you_pane() -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.custom_minimum_size.x = 320
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_child(UiTheme.label("YOU", UiTheme.FONT_SMALL, UiTheme.DIM))
	pane.add_child(_hands)
	pane.add_child(HSeparator.new())
	_lines.add_theme_constant_override("separation", 0)
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_child(_lines)
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size.y = 6
	var fill := UiTheme.box(UiTheme.ACCENT, Color.TRANSPARENT, 0)
	fill.set_content_margin_all(0)
	_weight_bar.add_theme_stylebox_override("fill", fill)
	var back := UiTheme.box(UiTheme.BG_HEADER)
	back.set_content_margin_all(0)
	_weight_bar.add_theme_stylebox_override("background", back)
	pane.add_child(_weight_text)
	pane.add_child(_weight_bar)
	return pane

func _process(_delta: float) -> void:
	var state := _state()
	visible = state != null and state.inventory_open and state.store_id == &""
	if not visible:
		_tip.hide_tip()
		_menu.visible = false
		return
	var key := "%s|%s|%d|%d" % [state.inventory, state.weapon, state.ammo, roundi(state.fame)]
	if key != _key:
		_key = key
		_rebuild(state)

func _rebuild(state: PlayerStateData) -> void:
	_hands.text = "Hands:  " + String(state.weapon).capitalize()
	for c in _lines.get_children():
		c.queue_free()
	var items := PlayerInputSystem.carried(state)
	for i in items.size():
		_lines.add_child(_item_row(i, items[i], state.inventory[items[i]]))
	for good in state.inventory:
		if not ItemCatalog.ITEMS.has(good) and state.inventory[good] > 0:
			_lines.add_child(_goods_row(good, state.inventory[good]))
	if _lines.get_child_count() == 0:
		_lines.add_child(UiTheme.label("Nothing. Stores sell food and water.", UiTheme.FONT_BODY, UiTheme.DIM))
	var kg := carried_kg(state)
	_weight_bar.max_value = ItemCatalog.CARRY_KG
	_weight_bar.value = minf(kg, ItemCatalog.CARRY_KG)
	_weight_text.text = "Weight %.1f / %.0f kg" % [kg, ItemCatalog.CARRY_KG]
	_weight_text.add_theme_color_override("font_color", UiTheme.BAD if kg > ItemCatalog.CARRY_KG else UiTheme.DIM)
	_rebuild_about(state)

static func carried_kg(state: PlayerStateData) -> float:
	var kg := 0.0
	for id in state.inventory:
		kg += ItemCatalog.item(id).get("weight", 0.0) * state.inventory[id]
	return kg

func _item_row(index: int, id: StringName, count: int) -> Button:
	var it := ItemCatalog.item(id)
	var row := _row_button("%d" % (index + 1) if index < 9 else "", it["name"], count, it.get("weight", 0.0) * count, it["kind"])
	row.pressed.connect(func() -> void: _state().ui_use = id)
	row.gui_input.connect(func(event: InputEvent) -> void: _on_row_input(event, id))
	row.mouse_entered.connect(func() -> void: _show_tip(id))
	row.mouse_exited.connect(_tip.hide_tip)
	return row

func _goods_row(good: StringName, count: int) -> Button:
	var row := _row_button("", String(good).capitalize(), count, 0.0, "goods")
	row.tooltip_text = "Sell it to a dealer"
	return row

func _row_button(key: String, text: String, count: int, kg: float, kind: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = UiTheme.ROW_H
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BG_ROW_HOVER, Color.TRANSPARENT, 0))
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	b.add_child(line)
	var chip := ColorRect.new()
	chip.color = KIND_COLOURS.get(kind, UiTheme.DIM)
	chip.custom_minimum_size = Vector2(4, UiTheme.ROW_H - 6)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for part in [UiTheme.label(" %s" % key if key != "" else "  ", UiTheme.FONT_BODY, UiTheme.ACCENT), chip,
			UiTheme.label("%s  x%d" % [text, count]), UiTheme.label("%.1f kg " % kg if kg > 0.0 else "", UiTheme.FONT_SMALL, UiTheme.DIM)]:
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(part)
	line.get_child(2).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

func _on_row_input(event: InputEvent, id: StringName) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_menu_item = id
		_tip.hide_tip()
		var kind: String = ItemCatalog.item(id)["kind"]
		_menu.open_at(get_global_mouse_position(), [
			{"text": VERBS.get(kind, "Use"), "enabled": VERBS.has(kind), "why": "load it by holding the pistol"},
			{"text": "Drop", "enabled": false, "why": "dropping comes with containers"},
		])

func _on_menu_pick(index: int) -> void:
	if index == 0 and _menu_item != &"":
		_state().ui_use = _menu_item

func _show_tip(id: StringName) -> void:
	var it := ItemCatalog.item(id)
	var lines: Array = [[String(it["kind"]).capitalize(), KIND_COLOURS.get(it["kind"], UiTheme.TEXT)]]
	for stat in ["hunger", "thirst", "tired", "heal"]:
		if it.has(stat):
			lines.append(["%s +%d%%" % [{"hunger": "Food", "thirst": "Water", "tired": "Energy", "heal": "Health"}[stat], roundi(it[stat] * 100)], UiTheme.GOOD])
	if it.has("weapon"):
		lines.append(["Damage %d" % roundi(CombatSystem.WEAPONS[it["weapon"]].get("damage", 0.0) * 100), UiTheme.TEXT])
	if it.has("rounds"):
		lines.append(["%d rounds" % it["rounds"], UiTheme.TEXT])
	lines.append(["%.1f kg   ·   $%d" % [it.get("weight", 0.0), it["price"]], UiTheme.DIM])
	_tip.show_at(get_global_mouse_position(), it["name"], lines)

func _rebuild_about(state: PlayerStateData) -> void:
	for c in _about.get_children():
		c.queue_free()
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	_about.add_child(UiTheme.label("CHARACTER", UiTheme.FONT_SMALL, UiTheme.DIM))
	_about.add_child(UiTheme.label("Rank: " + RankSystem.name_of(state.rank), UiTheme.FONT_BODY, UiTheme.ACCENT))
	_about.add_child(UiTheme.label("%d points to next" % RankSystem.to_next(_world, npc, state), UiTheme.FONT_SMALL, UiTheme.DIM))
	_about.add_child(UiTheme.label("Fame %d" % roundi(state.fame), UiTheme.FONT_SMALL))
	_about.add_child(UiTheme.label("Ammo %d rounds" % state.ammo, UiTheme.FONT_SMALL))
	_about.add_child(HSeparator.new())
	for s in Skills.NAMES:
		_about.add_child(UiTheme.label("%s  %d" % [String(s).capitalize(), Skills.level(state, s)], UiTheme.FONT_SMALL))
	_about.add_child(HSeparator.new())
	var traits := UiTheme.label("Traits: " + Traits.summary(state), UiTheme.FONT_SMALL, UiTheme.DIM)
	traits.autowrap_mode = TextServer.AUTOWRAP_WORD
	_about.add_child(traits)
	_about.add_child(UiTheme.label("Crew %d/%d   ·   businesses %d" % [state.crew_ids.size(), CrewSystem.MAX_CREW, BusinessSystem.count_owned(_world)], UiTheme.FONT_SMALL, UiTheme.DIM))

func _state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
