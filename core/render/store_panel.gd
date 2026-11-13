## G1/UI1: the open counter (what is on the shelf, price, what you carry).
class_name StorePanel
extends UiPanel

func refresh() -> void:
	var state := player_state()
	if state == null or state.store_id == &"":
		visible = false
		return
	var kind := ShopSystem.counter_kind(_world, state.store_id)
	var title: String = {"shop": "Store", "workshop": "Hardware", "dealer": "Dealer"}.get(kind, "Counter")
	var hrs := ShopSystem.hours_of(state.store_id, kind)
	var when := "any hour" if kind == "dealer" or hrs.y - hrs.x >= 24.0 else "%02d:00-%02d:00" % [int(hrs.x), int(hrs.y)]
	var rows: Array = []
	if not ShopSystem.is_open(_world, state.store_id):
		rows.append(["", "Closed. Opens at %02d:00." % int(hrs.x), ""])
	var stock := ItemCatalog.stock(kind)
	for i in stock.size():
		var it := ItemCatalog.item(stock[i])
		var have: int = state.ammo if it["kind"] == "ammo" else state.inventory.get(stock[i], 0)
		rows.append([str(i + 1), it["name"] + ("  (have %d)" % have if have > 0 else ""), "$%d" % it["price"]])
	show_panel("%s  ·  %s" % [title, when], rows, "Click or 1-9 to buy    E / Esc leave")
