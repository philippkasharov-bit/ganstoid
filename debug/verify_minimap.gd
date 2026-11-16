## MM1 validator: the GPS points at your waypoint, else your job; the route
## follows the streets (more than a straight line, ends at the goal); arriving
## clears the waypoint; a waypoint (and none) survive a save.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var city := TestWorlds.city()
	DriveSystem.graph = RoadGraph.build(city.roads)
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ok := true
	ok = _check(MiniMap.gps_goal(w, state) == null, "no waypoint, no job: no GPS") and ok
	var goal := me.position + Vector2(400, 250)
	state.waypoint = goal
	var route := MiniMap.gps_route(me.position, goal)
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	print("route: %d points, %.0f m (straight %.0f m)" % [route.size(), length, me.position.distance_to(goal)])
	ok = _check(MiniMap.gps_goal(w, state) == goal and route.size() > 3 and length >= me.position.distance_to(goal) and route[-1] == goal, "the GPS follows the streets to the waypoint") and ok
	var saved := var_to_str(SaveGame._fields(state))
	var back: Dictionary = str_to_var(saved)
	ok = _check(back["waypoint"] == goal, "a waypoint survives a save") and ok
	state.waypoint = Vector2.INF
	back = str_to_var(var_to_str(SaveGame._fields(state)))
	ok = _check(back["waypoint"] == Vector2.INF, "no waypoint survives a save") and ok
	state.waypoint = me.position + Vector2(5, 0)
	var ex := ExplorationSystem.new(w)
	ex.process_entities({PlayerFactory.PLAYER_ENTITY_ID: p}, 0.0, ExplorationSystem.PHASE)
	ok = _check(state.waypoint == Vector2.INF, "arriving clears the waypoint") and ok
	if ok:
		print("MINIMAP_VERIFY: PASS")
	quit(0 if ok else 1)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("MINIMAP_VERIFY: FAIL - ", what)
	return good
