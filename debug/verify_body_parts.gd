## HP1/HP2: Zomboid's 17-part body. Hits leave the right wound, bandages go on
## the worst bleeding part, bandages get dirty, open wounds fester and drain,
## hurt legs slow you, hurt arms spoil aim, parts heal, colours follow severity.
extends SceneTree

func _part(hp: float, wound: String, bleeding := false, bandaged := false) -> Dictionary:
	var b := BodyParts.fresh()
	b["hp"] = hp
	b["wound"] = wound
	b["bleeding"] = bleeding
	b["bandaged"] = bandaged
	return b

func _initialize() -> void:
	var world := World.new()
	world.runtime_rng.seed = 7
	var st := PlayerStateData.new()
	var npc := NPCData.new()
	var ok := true
	BodyParts.ensure(st)
	ok = ok and st.body.size() == 17
	st.body["l_leg"] = {"hp": 1.0}   # an old save's key is dropped
	BodyParts.ensure(st)
	ok = ok and not st.body.has("l_leg") and st.body.size() == 17
	var part := BodyParts.hit(world, st, {"damage": 0.2, "spread_hip_deg": 8.0})
	ok = ok and st.body[part]["wound"] == "bullet wound" and st.body[part]["bleeding"]
	var stab := BodyParts.hit(world, st, {"damage": 0.25})
	ok = ok and st.body[stab]["wound"] in ["deep wound", "bullet wound"]
	npc.bleeding = true
	ok = ok and BodyParts.bandage(st, npc) and BodyParts.bandage(st, npc) and not BodyParts.is_bleeding(st) and not npc.bleeding
	# Severity colours: bruise yellow, laceration orange, bleeding or deep red.
	ok = ok and BodyParts.severity(_part(0.9, "bruise")) == 1 and BodyParts.severity(_part(0.8, "laceration")) == 2
	ok = ok and BodyParts.severity(_part(0.8, "laceration", true)) == 3 and BodyParts.severity(_part(1.0, "")) == 0
	ok = ok and BodyDoll.colour_of(_part(0.8, "deep wound")) == BodyDoll.SEVERITY[3]
	# A bandage left a day gets dirty; an unbandaged cut festers into infection and drains.
	var st2 := PlayerStateData.new()
	BodyParts.ensure(st2)
	st2.body["r_forearm"] = _part(0.6, "laceration", false, true)
	st2.body["l_shin"] = _part(0.6, "laceration")
	var drain := BodyParts.heal(st2, 2.5)
	ok = ok and BodyParts.dirty(st2.body["r_forearm"]) and float(st2.body["l_shin"]["infection"]) >= 1.0 and drain > 0.0
	ok = ok and HealthWindow.injury_line("l_shin", st2.body["l_shin"]).contains("infected")
	ok = ok and HealthWindow.injury_line("r_forearm", st2.body["r_forearm"]).contains("dirty bandage")
	# Limbs: a broken thigh limps, a hurt hand spoils aim; breaks heal slowest.
	var st3 := PlayerStateData.new()
	BodyParts.ensure(st3)
	st3.body["l_thigh"] = _part(0.2, "fracture")
	ok = ok and BodyParts.move_mult(st3) < 0.5 and is_equal_approx(BodyParts.aim_mult(st3), 1.0)
	st3.body["r_hand"] = _part(0.3, "bruise")
	ok = ok and BodyParts.aim_mult(st3) > 1.2
	BodyParts.heal(st3, 3.0)
	ok = ok and st3.body["r_hand"]["wound"] == "" and st3.body["l_thigh"]["wound"] == "fracture"
	ok = ok and HealthWindow.injury_line("l_thigh", st3.body["l_thigh"]).begins_with("Left thigh: fracture")
	ok = ok and HealthWindow.injury_line("head", st3.body["head"]) == ""
	ok = ok and HealthWindow.status_word(0.95) == "Healthy" and HealthWindow.status_word(0.1) == "Critical"
	ok = ok and BodyDoll.SHAPES.size() == 17
	print("BODY_PARTS_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
