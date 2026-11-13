## R3D14 validator: walking into buildings. At a stranger's front door you
## are stopped ("Locked."); at your own you walk in through the door and are
## inside its footprint; inside, the walls hold you (walking far one way never
## takes you out through a wall); the kitchen cupboard opens only standing by
## its furniture.
extends SceneTree

func _initialize() -> void:
	var city := CityData.load_file()
	SimNav.install(city, city.spawn, 150.0)
	var b := _house(city)
	var l := InteriorLayout.of(b)
	var world := World.new()
	var bd := BuildingData.new()
	bd.id = b["id"]
	bd.building_type = GanstoidEnums.BuildingType.RESIDENCE
	var e := Entity.new(bd.id)
	e.add_component(bd)
	world.register_entity(e)
	var npc := NPCData.new()
	var st := PlayerStateData.new()
	var mid := l.door_a.lerp(l.door_b, 0.5)
	var out := (l.door_b - l.door_a).normalized().orthogonal()
	if Geometry2D.is_point_in_polygon(mid + out * 0.5, l.poly):
		out = -out
	var stranger := _walk(world, npc, st, mid + out * 1.5, -out, 3.0)
	var locked := st.last_message != ""
	npc.home_building_id = bd.id
	var home := _walk(world, npc, st, mid + out * 1.5, -out, 3.0)
	var inside := Geometry2D.is_point_in_polygon(home, l.poly)
	var held := true
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]:
		held = held and _only_by_door(world, npc, st, l, home, dir, 40.0)
	var reach := _reach(l)
	print("house %s: stranger stopped outside %s (said '%s'); own door lets you in %s; walls hold %s; cupboard only by its furniture %s" % [b["id"], not Geometry2D.is_point_in_polygon(stranger, l.poly), st.last_message, inside, held, reach])
	var ok := not Geometry2D.is_point_in_polygon(stranger, l.poly) and locked and inside and held and reach
	print("WALK_IN_VERIFY: %s" % ("PASS" if ok else "FAIL - doors or walls"))
	quit(0 if ok else 1)

## A house near the spawn with a front door and a kitchen cupboard.
func _house(city: CityData) -> Dictionary:
	for b in city.buildings:
		if b["kind"] == "house" and b["poly"][0].distance_to(city.spawn) < 150.0:
			var l := InteriorLayout.of(b)
			if l.door_a != l.door_b and l.furniture.any(func(f: Dictionary) -> bool: return f["container"] == "kitchen"):
				return b
	return {}

## Walk from `from` along `dir`: every time you pass in or out of the
## footprint it is through the front door, never a wall.
func _only_by_door(world: World, npc: NPCData, st: PlayerStateData, l: InteriorLayout, from: Vector2, dir: Vector2, metres: float) -> bool:
	npc.position = from
	for i in int(metres / 0.1):
		var was := npc.position
		npc.position = Indoors.step(world, npc, st, dir * 0.1)
		if Geometry2D.is_point_in_polygon(was, l.poly) != Geometry2D.is_point_in_polygon(npc.position, l.poly) and not InteriorSolid.at_door(l, was, 0.6):
			return false
	return true

## Walk `metres` from `from` along `dir` in 10 cm steps; where you end up.
func _walk(world: World, npc: NPCData, st: PlayerStateData, from: Vector2, dir: Vector2, metres: float) -> Vector2:
	npc.position = from
	for i in int(metres / 0.1):
		npc.position = Indoors.step(world, npc, st, dir * 0.1)
	return npc.position

func _reach(l: InteriorLayout) -> bool:
	for f in l.furniture:
		if f["container"] == "kitchen":
			var by: Vector2 = l.to_map((f["rect"] as Rect2).get_center())
			var far := _far_point(l, f["rect"])
			return not Indoors.out_of_reach(by, "kitchen") and (far == Vector2.INF or Indoors.out_of_reach(far, "kitchen"))
	return false

## A point inside the house well away from every kitchen piece (INF if the house is too small).
func _far_point(l: InteriorLayout, near: Rect2) -> Vector2:
	for p in l.local:
		var q := p.lerp(InteriorLayout._box(l.local).get_center(), 0.15)
		var clear := l.furniture.all(func(f: Dictionary) -> bool: return f["container"] != "kitchen" or not (f["rect"] as Rect2).grow(Indoors.REACH_M + 0.2).has_point(q))
		if clear and Geometry2D.is_point_in_polygon(q, l.local):
			return l.to_map(q)
	return Vector2.INF
