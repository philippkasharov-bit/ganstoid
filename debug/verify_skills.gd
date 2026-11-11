## S1 validator: levels from XP (25 n^2), edges of 5% a level, practice
## raises them (shots fired), and a level-up is announced.
extends SceneTree

func _initialize() -> void:
	var s := PlayerStateData.new()
	var l0 := Skills.level(s, &"shooting")
	Skills.gain(s, &"shooting", 100.0)
	var l2 := Skills.level(s, &"shooting")
	var less := Skills.less(s, &"shooting")
	Skills.gain(s, &"shooting", 5000.0)
	var top := Skills.level(s, &"shooting")
	var t := PlayerStateData.new()
	var serial := t.message_serial
	for i in 25:
		Skills.train(null, t, &"melee", 1.0)
	print("levels %d -> %d -> %d (cap), spread x%.2f at 2; melee after 25 XP: level %d, announced %s" % [l0, l2, top, less, Skills.level(t, &"melee"), t.message_serial > serial])
	if l0 == 0 and l2 == 2 and top == 10 and absf(less - 0.9) < 0.001 and Skills.level(t, &"melee") == 1 and t.message_serial > serial:
		print("SKILLS_VERIFY: PASS")
		quit()
	else:
		print("SKILLS_VERIFY: FAIL - skill levels and edges")
		quit(1)
