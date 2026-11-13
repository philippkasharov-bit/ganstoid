## G1/UI1/TR1: the counter as Project Zomboid's trade window. Left: what is on
## the shelf (picture, name, how many you have, price); a click or 1-9 puts
## one in the basket. Right: your basket with a running total against your
## cash, "-" to take one out, Buy (or Enter) to pay for it all, Clear to put
## it back. Hover a line for the item card. Writes state.ui_pick, basket
## edits and state.ui_buy; the input system does the buying.
class_name StorePanel
extends UiWindow

const SIDE_W := 220.0
const ROW_H := 26.0
const ICON := 22.0

var _world: World
var _shelf := VBoxContainer.new()
var _basket := VBoxContainer.new()
var _total := UiTheme.label("", UiTheme.FONT_BODY)
var _cash := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DIM)
var _buy := Button.new()
var _clear := Button.new()
var _tip := UiTooltip.new()
var _key := ""

func setup(world: World, at: Vector2) -> void:
	_world = world
	setup_window("store", "Store", at, Vector2(0, 0))
	closed.connect(func() -> void:
		var st := _state()
		if st != null:
			st.store_id = &""
			st.basket = {})
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	body.add_child(split)
	split.add_child(_side("On the shelf", _shelf))
	var right := _side("Your basket", _basket)
	right.add_child(UiTheme.divider())
	right.add_child(_total)
	right.add_child(_cash)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UiTheme.GAP)
	for b in [_buy, _clear]:
		_style(b)
		buttons.add_child(b)
	_clear.text = "Clear"
	_buy.pressed.connect(func() -> void: _state().ui_buy = true)
	_clear.pressed.connect(func() -> void: _state().basket = {})
	right.add_child(buttons)
	split.add_child(right)
	body.add_child(UiTheme.key_hints([["1-9", "add"], ["Enter", "buy"], ["E", "leave"]]))
	add_child(_tip)
	_tip.top_level = true
	visible = false

static func _side(title: String, list: VBoxContainer) -> VBoxContainer:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = SIDE_W
	side.add_theme_constant_override("separation", UiTheme.GAP)
	side.add_child(UiTheme.label(title, UiTheme.FONT_SMALL, UiTheme.DIM))
	list.add_theme_constant_override("separation", 0)
	side.add_child(list)
	return side

static func _style(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	for look in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(look, UiTheme.button_box(look))

func _process(_delta: float) -> void:
	var state := _state()
	visible = state != null and state.store_id != &""
	if not visible:
		_tip.hide_tip()
		return
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var open := ShopSystem.is_open(_world, state.store_id)
	var key := "%s|%s|%s|%d|%d|%s" % [state.store_id, state.basket, state.inventory, state.ammo, npc.cash, open]
	if key != _key:
		_key = key
		_rebuild(state, npc, open)

func _rebuild(state: PlayerStateData, npc: NPCData, open: bool) -> void:
	var kind := ShopSystem.counter_kind(_world, state.store_id)
	var hrs := ShopSystem.hours_of(state.store_id, kind)
	var when := "any hour" if kind == "dealer" or hrs.y - hrs.x >= 24.0 else "%02d:00-%02d:00" % [int(hrs.x), int(hrs.y)]
	set_title("%s  ·  %s" % [{"shop": "Store", "workshop": "Hardware", "dealer": "Dealer"}.get(kind, "Counter"), when])
	_clear_box(_shelf)
	if not open:
		_shelf.add_child(UiTheme.label("Closed. Opens at %02d:00." % int(hrs.x), UiTheme.FONT_SMALL, UiTheme.BAD))
	var stock := ItemCatalog.stock(kind)
	for i in stock.size():
		var it := ItemCatalog.item(stock[i])
		var have: int = state.ammo if it["kind"] == "ammo" else int(state.inventory.get(stock[i], 0))
		_shelf.add_child(_line(stock[i], str(i + 1) if i < 9 else "", "have %d" % have if have > 0 else "", "$%d" % it["price"], func() -> void: state.ui_pick = i))
	_clear_box(_basket)
	for id in state.basket:
		var n := int(state.basket[id])
		_basket.add_child(_line(id, "-", "x%d" % n, "$%d" % (int(ItemCatalog.item(id)["price"]) * n), func() -> void:
			state.basket[id] = n - 1
			if state.basket[id] <= 0:
				state.basket.erase(id)))
	if state.basket.is_empty():
		_basket.add_child(UiTheme.label("Empty. Click a shelf line to add it.", UiTheme.FONT_SMALL, UiTheme.DIM))
	var total := ShopSystem.basket_total(state.basket)
	var short := total > npc.cash
	_total.text = "Total  $%d" % total
	_cash.text = "Your cash  $%d%s" % [npc.cash, "  (short $%d)" % (total - npc.cash) if short else ""]
	_cash.add_theme_color_override("font_color", UiTheme.BAD if short else UiTheme.DIM)
	_buy.text = "Buy  $%d" % total
	_buy.disabled = state.basket.is_empty() or short or not open
	_clear.disabled = state.basket.is_empty()

static func _clear_box(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

## One line: key badge (or "-" to take out), picture, name, note, price.
func _line(id: StringName, badge: String, note: String, price: String, on_click: Callable) -> Button:
	var it := ItemCatalog.item(id)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(SIDE_W, ROW_H)
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BG_ROW_HOVER, Color.TRANSPARENT, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(UiTheme.label(" %s " % badge if badge != "" else "   ", UiTheme.FONT_SMALL, UiTheme.ACCENT if badge != "-" else UiTheme.BAD))
	var art := Control.new()
	art.custom_minimum_size = Vector2(ICON, ICON)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.draw.connect(func() -> void: ItemArt.draw(art, id, Rect2(Vector2.ZERO, Vector2(ICON, ICON)), InventoryWindow.KIND_COLOURS.get(it["kind"], UiTheme.DIM), false))
	row.add_child(art)
	var name_label := UiTheme.label(it["name"], UiTheme.FONT_SMALL, UiTheme.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	if note != "":
		row.add_child(UiTheme.label(note, 10, UiTheme.DIM))
	row.add_child(UiTheme.label(price, UiTheme.FONT_SMALL, UiTheme.ACCENT))
	for c in row.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	b.pressed.connect(on_click)
	b.mouse_entered.connect(func() -> void: _tip.show_at(b.get_global_rect().end - Vector2(0, ROW_H), it["name"], ItemCard.lines(id)))
	b.mouse_exited.connect(_tip.hide_tip)
	return b

func _state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
