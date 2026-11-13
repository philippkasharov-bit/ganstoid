## HP1: hits land on a part and leave the right wound, bandages go on the worst
## bleeding part, hurt legs slow you, hurt arms spoil aim, parts heal.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	world.runtime_rng.seed = 7
	var st := PlayerStateData.new()
	var npc := NPCData.new()
	var bullet := {"damage": 0.2, "spread_hip_deg": 8.0}
	var part := BodyParts.hit(world, st, bullet)
	var ok: bool = st.body[part]["wound"] == "bullet wound" and st.body[part]["bleeding"] and st.body[part]["hp"] < 1.0
	var bruise := BodyParts.hit(world, st, {"damage": 0.1, "blunt": true})
	ok = ok and (st.body[bruise]["wound"] in ["bruise", "bullet wound", "fracture"])
	npc.bleeding = true
	ok = ok and BodyParts.bandage(st, npc) and st.body[part]["bandaged"] and not st.body[part]["bleeding"] and not npc.bleeding
	st.body["l_leg"] = {"hp": 0.2, "wound": "fracture", "bleeding": false, "bandaged": false}
	ok = ok and BodyParts.move_mult(st) < 0.5 and BodyParts.aim_mult(st) <= 1.0
	st.body["r_arm"]["hp"] = 0.3
	ok = ok and BodyParts.aim_mult(st) > 1.2
	BodyParts.heal(st, 3.0)
	ok = ok and st.body["r_arm"]["hp"] >= 0.95 and st.body["r_arm"]["wound"] == "" and st.body["l_leg"]["wound"] == "fracture"   # breaks heal slowest
	ok = ok and HealthWindow.injury_line("l_leg", st.body["l_leg"]).begins_with("Left leg: fracture")
	print("BODY_PARTS_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
