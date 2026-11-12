## T1: time reads from the start of a life (Day N, Year/Month, "you lasted").
extends SceneTree

func _initialize() -> void:
	var d := SimClock.day_ticks
	var ok := SimClock.day_number(0) == 1 and SimClock.day_number(d * 46 + 5) == 47
	ok = ok and SimClock.year_month(0) == "Year 1, Month 1" and SimClock.year_month(d * 45) == "Year 1, Month 2"
	ok = ok and SimClock.year_month(d * 365) == "Year 2, Month 1"
	ok = ok and SimClock.lasted(0.5) == "12 hours" and SimClock.lasted(1.2) == "1 day"
	ok = ok and SimClock.lasted(462.0) == "1 year, 3 months, 12 days"
	print("TIME_COUNTER_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
