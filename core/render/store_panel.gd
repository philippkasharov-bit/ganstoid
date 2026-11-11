## G1: the open counter's menu (what is on the shelf, price, what you carry).
## Read-only view of PlayerStateData.store_id; PlayerInputSystem does the buying.
class_name StorePanel
extends Label

var _world: World

func setup(world: World) -> void:
	_world = world
	position = Vector2(12, 230)
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)

func _process(_delta: float) -> void:
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE) if player != null else null
	visible = state != null and state.store_id != &""
	if visible:
		text = format(_world, state)

static func format(world: World, state: PlayerStateData) -> String:
	var kind := ShopSystem.counter_kind(world, state.store_id)
	var title: String = {"shop": "SHOP", "workshop": "HARDWARE", "dealer": "DEALER (no questions)"}.get(kind, "COUNTER")
	var hrs := ShopSystem.hours_of(state.store_id, kind)
	var lines: PackedStringArray = ["-- %s (%s) --" % [title, "any hour" if kind == "dealer" or hrs.y - hrs.x >= 24.0 else "%02d:00-%02d:00" % [int(hrs.x), int(hrs.y)]]]
	if not ShopSystem.is_open(world, state.store_id):
		var h := ShopSystem.hours_of(state.store_id, kind)
		lines.append("Closed. Opens at %02d:00." % int(h.x))
	var stock := ItemCatalog.stock(kind)
	for i in stock.size():
		var it := ItemCatalog.item(stock[i])
		var have: int = state.ammo if it["kind"] == "ammo" else state.inventory.get(stock[i], 0)
		lines.append("%d. %s - $%d%s" % [i + 1, it["name"], it["price"], ("   (have %d)" % have) if have > 0 else ""])
	lines.append("")
	lines.append("1-9: buy   E or Esc: leave")
	return "\n".join(lines)
