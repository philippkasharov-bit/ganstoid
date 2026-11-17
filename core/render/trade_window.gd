## UI7: the deal window (sell to the person in front of you: what you carry,
## its grade and strain, what it's worth, your price with -/+, how likely
## they are to bite, Offer) and the pawn / fence window (each valuable with
## what it fetches, sell one or all). Read-only: buttons ask (ui_trade).
class_name TradeWindow
extends PanelContainer

const W := 420.0
const GOODS := [&"weed", &"pills", &"meth", &"coke", &"heroin"]

var _world: World
var _col := VBoxContainer.new()
var _key := ""

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiPanel.card_style())
	_col.add_theme_constant_override("separation", 6)
	_col.custom_minimum_size.x = W
	add_child(_col)
	visible = false

func _process(_delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
	visible = state != null and not state.trade.is_empty()
	if not visible:
		_key = ""
		return
	if Input.is_action_just_pressed("ui_cancel"):
		state.ui_trade = {"op": "close"}
	var key := str(state.trade) + str(state.inventory) + str(state.prices) + str(_world.tick / 60)
	if key != _key:
		_key = key
		_build(state, p.get_component(ComponentNames.NPC))
	var view := get_viewport_rect().size
	position = ((view - size) * 0.5).round()

func _build(state: PlayerStateData, me: NPCData) -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var t := state.trade
	if t["mode"] == "deal":
		_deal(state, me, t)
	else:
		_pawn(state, t)
	var line: String = t.get("line", "")
	if line != "":
		_col.add_child(UiTheme.label(line, UiTheme.FONT_SMALL, UiTheme.GOOD if int(t.get("tone", 0)) > 0 else UiTheme.BAD))
	_row([["Close (Esc)", {"op": "close"}]], state)
	reset_size()

func _deal(state: PlayerStateData, me: NPCData, t: Dictionary) -> void:
	var e: Entity = _world.entities.get(t["who"])
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	if n == null:
		return
	_head("DEAL", n.display_name)
	var rel := Relation.of(_world, state, n)
	var wealth := float(BlockEconomyData.block_at(_world, n.position).get("wealth", 0.5))
	var who: String = (rel[1] if not rel.is_empty() else "A stranger") + " · " + BlockEconomyData.describe(wealth).to_lower() + " block"
	if wealth < 0.35:
		who += ": lots of users here"
	var who_col: Color = rel[0] if not rel.is_empty() else UiTheme.DIM
	_col.add_child(UiTheme.label(who, UiTheme.FONT_SMALL, who_col))
	_col.add_child(UiTheme.divider())
	for good in GOODS:
		var have := int(state.inventory.get(good, 0))
		if have <= 0:
			continue
		var q := DrugLabSystem.stars(state, good)
		_col.add_child(UiTheme.label("%s · %s · you carry %d" % [String(good).capitalize(), Grades.drug_text(good, q), have], UiTheme.FONT_BODY, UiTheme.TEXT))
		var about := Grades.about(state, good)
		if about != "":
			_col.add_child(UiTheme.label(about, UiTheme.FONT_SMALL, UiTheme.DIM))
		var worth := DrugLabSystem.value_each(_world, state, good, n.position, false)
		var ask := DrugLabSystem.ask_each(_world, state, good, n.position, false)
		var bite := roundi(DrugLabSystem.accept(ask, worth) * 100.0)
		_col.add_child(UiTheme.label("worth about $%d to them · you ask $%d · %d%% would take it" % [roundi(worth), ask, bite], UiTheme.FONT_SMALL, UiTheme.GOOD if bite >= 80 else (UiTheme.ACCENT if bite >= 40 else UiTheme.BAD)))
		var buttons := []
		for d in [-5, -1, 1, 5]:
			buttons.append(["%+d" % d, {"op": "price", "good": good, "set": maxi(1, ask + d)}])
		buttons.append(["fair", {"op": "price", "good": good, "set": 0}])
		buttons.append(["Offer $%d" % ask, {"op": "offer", "good": good}])
		_row(buttons, state)
		_col.add_child(UiTheme.divider())

func _pawn(state: PlayerStateData, t: Dictionary) -> void:
	var pawn: bool = t["mode"] == "pawn"
	var share := TradeSystem.share_of(t["mode"])
	var title: String = {"pawn": "PAWN SHOP", "ring": "YOUR RING"}.get(t["mode"], "FENCE")
	_head(title, "clean cash, %d%% of worth" % roundi(share * 100) if pawn else "no questions, %d%%, dirty cash" % roundi(share * 100))
	_col.add_child(UiTheme.divider())
	var any := false
	for id in state.inventory:
		var it := ItemCatalog.item(id)
		if it.get("kind", "") != "valuable":
			continue
		any = true
		var row := HBoxContainer.new()
		var l := UiTheme.label("%s ×%d · $%d each" % [it["name"], int(state.inventory[id]), roundi(int(it["price"]) * share)], UiTheme.FONT_SMALL, UiTheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_button("Sell one", {"op": "sell", "id": id}, state))
		_col.add_child(row)
	if not any:
		_col.add_child(UiTheme.label("Nothing they'd buy. Valuables come from searching homes and pockets.", UiTheme.FONT_SMALL, UiTheme.DIM))
	else:
		_row([["Sell everything ($%d)" % Fence.worth(state, share), {"op": "sell_all"}]], state)

func _head(title: String, sub: String) -> void:
	var l := UiTheme.label(title, 22, UiTheme.ACCENT)
	l.add_theme_font_override("font", UiTheme.font("marker"))
	_col.add_child(l)
	_col.add_child(UiTheme.label(sub, UiTheme.FONT_SMALL, UiTheme.DIM))

func _row(buttons: Array, state: PlayerStateData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for spec in buttons:
		row.add_child(_button(spec[0], spec[1], state))
	_col.add_child(row)

func _button(text: String, ask: Dictionary, state: PlayerStateData) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	for look in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(look, UiTheme.button_box(look))
	b.pressed.connect(func() -> void: state.ui_trade = ask)
	return b
