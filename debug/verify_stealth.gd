## ST2 validator: the police only know where you are while they can see you.
## A crime is reported at night; the officer called to it goes to the scene,
## not to you hiding 60 m away in the dark, looks round there and gives up.
## The same officer standing in daylight a few metres away does see you, and
## a cop never sees you in the dark from further than the light allows.
extends SceneTree

func _initialize() -> void:
	var saved := SimClock.day_ticks
	var w := World.new()
	SystemRegistry.register_all(w)
	TestWorlds.real_city(w, 4242)
	var city := TestWorlds.city()
	StreetLights.active = StreetLights.build(city, city.spawn, 400.0)
	SimNav.install(city, city.spawn, 300.0)
	await TestWorlds.wait_nav(self, [SimNav.active])
	var p: Entity = w.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var cops := w.find_system(CopAISystem) as CopAISystem
	var ok := true
	SimClock.day_ticks = SimClock.DEFAULT_DAY_TICKS   # the game's clock (test worlds run a short day): 45 s must stay night
	w.tick = SimClock.hours(24.0 + 23.0)   # 23:00
	var scene := _dark_spot(w, me.position, 0.0)
	var hide := _dark_spot(w, scene, 60.0)
	print("crime scene light %.2f, hiding spot light %.2f, %d m apart" % [StreetLights.light_at(scene, 23.0), StreetLights.light_at(hide, 23.0), roundi(scene.distance_to(hide))])
	var cop: NPCData = null
	for e in w.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.is_cop and not n.is_down:
			if cop == null:
				cop = n
			else:
				n.position = Vector2(-10000, -10000)   # only one officer in this test
				w.reindex_position(n.id)
	cop.position = scene + Vector2(30, 0)
	w.reindex_position(cop.id)
	state.law_tier = GanstoidEnums.LawTier.WARNED
	me.position = hide
	w.reindex_position(me.id)
	cops.on_crime_witnessed(GanstoidEvents.CRIME_WITNESSED, {"position": scene})
	var h: Array = cops.hunters()
	ok = _check(h.size() == 1 and (h[0][1] as Vector2) == scene, "CH1: the minimap sees the officer heading for the scene, not for you") and ok
	var closest := INF
	var at_scene := INF
	for t in 60 * 45:   # 45 s
		w.tick += 1
		cops.process_entities(w.get_entities_with_component(ComponentNames.NPC), 1.0 / 60.0, w.tick)
		closest = minf(closest, cop.position.distance_to(hide))
		at_scene = minf(at_scene, cop.position.distance_to(scene))
	print("officer: closest to the scene %.1f m, closest to you %.1f m, law tier %d" % [at_scene, closest, state.law_tier])
	ok = _check(at_scene < 5.0, "the officer goes to the crime scene") and ok
	ok = _check(closest > 20.0 and state.law_tier != GanstoidEnums.LawTier.CLEAN, "hidden in the dark 60 m away you are not found") and ok
	print("hour %.1f light here %.2f" % [SimClock.day_fraction(w.tick) * 24.0, StreetLights.light_at(hide, SimClock.day_fraction(w.tick) * 24.0)])
	ok = _check(not CrimeSystem.can_see(w, hide + Vector2(12, 0), hide, true), "a searching cop 12 m away can't see you in the dark") and ok
	w.tick = SimClock.hours(24.0 + 13.0)   # 13:00
	ok = _check(CrimeSystem.can_see(w, hide + Vector2(12, 0), hide), "by day the same 12 m is in sight") and ok
	StreetLights.active = null
	SimNav.uninstall()
	SimClock.day_ticks = saved
	if ok:
		print("STEALTH_VERIFY: PASS")
	quit(0 if ok else 1)

## A dark point (no lamp) on open ground about `dist` m from `near`.
func _dark_spot(w: World, near: Vector2, dist: float) -> Vector2:
	for k in 400:
		var a := k * 0.37
		var r := dist + (k % 20) * 2.0
		var q := SimNav.active.snap(near + Vector2.from_angle(a) * r, "public")
		if StreetLights.light_at(q, 23.0) <= 0.3 and absf(q.distance_to(near) - dist) < 25.0 and SimNav.active.collision.line_clear(q, q + Vector2(12, 0), 0.0):
			return q
	return near + Vector2(dist, 0)

func _check(good: bool, what: String) -> bool:
	if not good:
		print("STEALTH_VERIFY: FAIL - ", what)
	return good
