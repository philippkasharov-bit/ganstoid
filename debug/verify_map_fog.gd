## MP2 validator: the map's fog of war. A new life knows its neighbourhood
## and nothing further; walking reveals more and it stays revealed; a shop
## only shows on the map once its spot is explored; a dealer you have seen up
## close is remembered; gang turf shows only on explored blocks; the fog and
## the people you know are saved.
extends SceneTree

func _initialize() -> void:
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var city := TestWorlds.city()
	SimNav.install(city, city.spawn, 200.0)
	await TestWorlds.wait_nav(self, [SimNav.active])
	w.tick = SimClock.hours(36.0)   # midday: dealers are seen at 20 m
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var ex := ExplorationSystem.new(w)
	var players := {PlayerFactory.PLAYER_ENTITY_ID: p}
	ex.process_entities(players, 0.0, 0 + ExplorationSystem.PHASE)
	var ok := true
	var start := ExplorationSystem.count(state)
	var far := me.position + Vector2(800, 0)
	print("start: %d cells known" % start)
	ok = _check(start > 200 and ExplorationSystem.explored(state, me.position) and not ExplorationSystem.explored(state, far), "a new life knows its neighbourhood, not the far side") and ok
	var view := CityMapView.new()
	view.world = w
	view.city = city
	var shop := _shop_beyond(w, me.position, 400.0)
	view._collect()
	ok = _check(shop != null and not _marked(view, shop.position), "an unexplored shop is not on the map") and ok
	var home := me.position
	me.position = shop.position
	ex.process_entities(players, 0.0, 30 + ExplorationSystem.PHASE)
	me.position = home
	ex.process_entities(players, 0.0, 60 + ExplorationSystem.PHASE)
	view._collect()
	ok = _check(_marked(view, shop.position) and ExplorationSystem.explored(state, shop.position), "once you've been there it stays on the map") and ok
	var dealer: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.is_dealer and not n.is_down:
			dealer = n
			break
	me.position = dealer.position + Vector2(0.5, 0)
	w.reindex_position(me.id)
	ex.process_entities(players, 0.0, 90 + ExplorationSystem.PHASE)
	ok = _check(state.known.get(dealer.id, "") == "dealer", "a dealer you've seen is remembered") and ok
	view._collect()
	var t := TerritorySystem.data(w)
	var hidden := 0
	var shown := view._turf.size()
	for c in t.cells:
		if TerritorySystem.controller(t, c) != &"" and Hoods.is_block(c) and not ExplorationSystem.explored(state, Hoods.data().block(c)["c"]):
			hidden += 1
	print("turf blocks on the map %d, still under fog %d" % [shown, hidden])
	ok = _check(hidden > 0, "gang turf you haven't walked stays hidden") and ok
	var fields := SaveGame._fields(state)
	ok = _check(fields.has("explored") and fields.has("known"), "fog and known people are saved") and ok
	state.explored = PackedByteArray([1, 2, 3])   # a damaged save
	ok = _check(not ExplorationSystem.explored(state, me.position), "a damaged fog reads as unexplored, no crash") and ok
	view.free()
	SimNav.uninstall()
	if ok:
		print("MAP_FOG_VERIFY: PASS")
	quit(0 if ok else 1)

func _shop_beyond(w: World, from: Vector2, d: float) -> BuildingData:
	for e in w.get_entities_with_component(ComponentNames.BUILDING).values():
		var b: BuildingData = e.get_component(ComponentNames.BUILDING)
		if ShopSystem.counter_kind(w, b.id) != "" and b.position.distance_to(from) > d and b.position.distance_to(from) < d + 300.0:
			return b
	return null

func _marked(view: CityMapView, at: Vector2) -> bool:
	for m in view._marks:
		if (m[0] as Vector2).distance_to(at) < 0.5:
			return true
	return false

func _check(good: bool, what: String) -> bool:
	if not good:
		print("MAP_FOG_VERIFY: FAIL - ", what)
	return good
