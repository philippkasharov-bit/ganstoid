## BZ3: the back-room table. Blackjack (your cards, the dealer's, hit or
## stand) and street dice, bets of $10, $50 or $200, and how you're doing
## tonight. Read-only: every button only asks (ui_gamble).
class_name GambleWindow
extends PanelContainer

var _world: World
var _col := VBoxContainer.new()
var _key := ""

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiPanel.card_style())
	_col.add_theme_constant_override("separation", 6)
	add_child(_col)
	visible = false

func _process(_delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE) if p != null else null
	visible = state != null and not state.gamble.is_empty()
	if not visible:
		_key = ""
		return
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var key := str(state.gamble) + str(me.cash)
	if key != _key:
		_key = key
		_build(state, me)
	var view := get_viewport_rect().size
	position = ((view - size) * 0.5).round()

func _build(state: PlayerStateData, me: NPCData) -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var g := state.gamble
	var title := UiTheme.label("BACK ROOM", 22, UiTheme.ACCENT)
	title.add_theme_font_override("font", UiTheme.font("marker"))
	_col.add_child(title)
	_col.add_child(UiTheme.label("cash $%d  ·  tonight %s$%d" % [me.cash, "+" if int(g.get("net", 0)) >= 0 else "-", absi(int(g.get("net", 0)))], UiTheme.FONT_SMALL, UiTheme.DIM))
	_col.add_child(UiTheme.divider())
	if not (g.get("you", []) as Array).is_empty():
		var hide: bool = g["stage"] == "play"
		var dealer: String = (GambleSystem.CARD[int(g["dealer"][0])] + " ?") if hide else "%s  (%d)" % [GambleSystem.hand_text(g["dealer"]), GambleSystem.total(g["dealer"])]
		_col.add_child(UiTheme.label("Dealer:  " + dealer, UiTheme.FONT_TITLE, UiTheme.TEXT))
		_col.add_child(UiTheme.label("You:     %s  (%d)" % [GambleSystem.hand_text(g["you"]), GambleSystem.total(g["you"])], UiTheme.FONT_TITLE, UiTheme.ACCENT))
	if g.has("rolls"):
		_col.add_child(UiTheme.label("Dice: " + " · ".join((g["rolls"] as Array).map(func(r: int) -> String: return str(r))), UiTheme.FONT_TITLE, UiTheme.TEXT))
	var line: String = g.get("line", "")
	_col.add_child(UiTheme.label(line, UiTheme.FONT_SMALL, UiTheme.GOOD if line.contains("win") or line.contains("Blackjack") else (UiTheme.BAD if line.contains("lose") else UiTheme.TEXT)))
	_col.add_child(UiTheme.divider())
	if g["stage"] == "play":
		_row([["Hit", {"op": "hit"}], ["Stand", {"op": "stand"}]], state)
	else:
		_row(GambleSystem.BETS.map(func(b: int) -> Array: return ["Cards $%d" % b, {"op": "deal", "bet": b}]), state)
		_row(GambleSystem.BETS.map(func(b: int) -> Array: return ["Dice $%d" % b, {"op": "dice", "bet": b}]), state)
	_row([["Leave the table", {"op": "leave"}]], state)
	reset_size()

func _row(buttons: Array, state: PlayerStateData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for spec in buttons:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		var ask: Dictionary = spec[1]
		b.pressed.connect(func() -> void: state.ui_gamble = ask)
		row.add_child(b)
	_col.add_child(row)
