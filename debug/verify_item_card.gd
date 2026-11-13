## IT1: item cards show bars: damage / reach / speed on weapons, food / water
## / energy / health on the rest, then one line of weight, size and price.
extends SceneTree

func _initialize() -> void:
	var gun := ItemCard.lines(&"pistol")
	var labels: Array = gun.filter(func(l: Array) -> bool: return l[0] == "bar").map(func(l: Array) -> String: return l[1])
	var ok: bool = labels == ["Damage", "Reach", "Speed"] and gun[-1][0].contains("kg")
	var burrito := ItemCard.lines(&"burrito")
	ok = ok and burrito[1][0] == "bar" and burrito[1][1] == "Food" and burrito[1][4] == "+50%" and is_equal_approx(burrito[1][2], 1.0)
	var row := UiTooltip.bar_row(["bar", "Food", 0.4, UiTheme.GOOD, "+20%"])
	ok = ok and row.get_child_count() == 3
	row.free()
	print("ITEM_CARD_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
