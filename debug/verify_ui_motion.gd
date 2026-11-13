## A1-A3: moodle tiles slide in, show an arrow when they change (red down when
## worse, green up when better) and slide out when they clear; eating floats
## "+Food"; a hit flashes and remembers the part.
extends SceneTree

func _row(lvl: int) -> Array:
	return ["hunger", ["Peckish", "Hungry"][lvl - 1], lvl, false, "", "food", "Food 40%"]

func _anim(m: Moodles) -> Array:
	var out: Array = []
	for c in m.get_children():
		if c.has_meta("anim"):
			out.append(String(c.get_meta("anim")))
	return out

func _initialize() -> void:
	await process_frame
	var m := Moodles.new()
	root.add_child(m)
	m._rebuild([_row(1)])
	var ok := _anim(m) == ["in"]
	m._rebuild([_row(2)])
	ok = ok and _anim(m) == ["worse"]
	m._rebuild([_row(1)])
	ok = ok and _anim(m) == ["better"]
	m._rebuild([])
	ok = ok and _anim(m) == ["out"] and m.get_child(m.get_child_count() - 1).get_child_count() == 2   # face + arrow
	var h := HaloText.new()
	var npc := NPCData.new()
	npc.hunger = 0.3
	h._gains(npc)
	npc.hunger = 0.8
	h._gains(npc)
	ok = ok and h._lines.size() == 1 and h._lines[0]["text"] == "+Food 50%"
	h.free()
	var world := World.new()
	world.runtime_rng.seed = 3
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	var st := PlayerStateData.new()
	var e := Entity.new(me.id)
	e.add_component(me)
	e.add_component(st)
	world.register_entity(e)
	CombatSystem._hurt(world, me, {"damage": 0.1})
	ok = ok and st.hurt_serial == 1 and BodyParts.NAMES.has(st.hurt_part)
	# A5: a pick-up flies from Nearby to the bag, a drop the other way.
	var holder := Control.new()
	root.add_child(holder)
	ItemFlight.between(holder, {&"water": 1}, {&"water": 2, &"chips": 0}, {&"water": Vector2(10, 10)}, {}, {}, {&"water": Vector2(200, 50)})
	ok = ok and holder.get_child_count() == 1 and holder.get_child(0) is ItemFlight
	# A7: a level gained shines the box just earned.
	var sk := SkillsPanel.new()
	root.add_child(sk)
	var ps := PlayerStateData.new()
	ps.skills = {&"melee": 30.0}
	sk.refresh(ps)
	ps.skills = {&"melee": 120.0}
	sk.refresh(ps)
	ok = ok and sk._shine.has(&"melee")
	print("UI_MOTION_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
