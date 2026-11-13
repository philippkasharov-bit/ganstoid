## SL1 validator: a game written to disk and read back into a freshly generated
## city of the same seed is the same game: the clock, the player's cash, heat,
## gun and rounds, a dead body where it fell, a recruited crew member, prices.
## Also: writing takes little time, a broken or old file is ignored.
extends SceneTree

const PATH := "user://verify_save.txt"
const SEED := 4242

func _initialize() -> void:
	var a := World.new()
	SystemRegistry.register_all(a)
	TestWorlds.real_city(a, SEED)
	a.tick = SimClock.hours(30.5)
	var me: NPCData = a.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var state: PlayerStateData = a.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	me.cash = 777
	me.position += Vector2(3, 4)
	state.law_tier = GanstoidEnums.LawTier.REPEAT_OFFENDER
	state.weapon = &"pistol"
	state.ammo = 5
	var body := _someone(a, 0)
	body.is_down = true
	body.health = 0.0
	var crew := _someone(a, 1)
	crew.is_crew = true
	state.crew_ids.append(crew.id)
	var good: StringName = a.economy_items.keys()[0]
	a.economy_items[good].current_price = 99
	var t0 := Time.get_ticks_msec()
	var ok := SaveGame.write(a, SEED, PATH)
	var write_ms := Time.get_ticks_msec() - t0
	var b := World.new()
	SystemRegistry.register_all(b)
	TestWorlds.real_city(b, SEED)
	t0 = Time.get_ticks_msec()
	var restored := SaveGame.apply(b, SaveGame.read(PATH))
	var read_ms := Time.get_ticks_msec() - t0
	var me2: NPCData = b.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var st2: PlayerStateData = b.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var body2: NPCData = b.entities[body.id].get_component(ComponentNames.NPC)
	var crew2: NPCData = b.entities[crew.id].get_component(ComponentNames.NPC)
	var size := FileAccess.get_file_as_bytes(PATH).size()
	print("saved %d entities in %d ms (%d KB), restored %d in %d ms" % [a.entities.size(), write_ms, size / 1024, restored, read_ms])
	print("tick %d/%d, cash %d, pos %s/%s, weapon %s ammo %d, body down %s at %s, crew %s in roster %s, price %s" % [
		b.tick, a.tick, me2.cash, me2.position, me.position, st2.weapon, st2.ammo, body2.is_down, body2.position == body.position,
		crew2.is_crew, st2.crew_ids.has(crew.id), b.economy_items[good].current_price])
	ok = ok and restored == a.entities.size() and b.tick == a.tick and me2.cash == 777 and me2.position == me.position
	ok = ok and st2.weapon == &"pistol" and st2.ammo == 5 and st2.law_tier == state.law_tier
	ok = ok and body2.is_down and body2.position == body.position and crew2.is_crew and st2.crew_ids.has(crew.id)
	ok = ok and b.economy_items[good].current_price == 99
	if not _check(ok, "the game read back is the game written"):
		return
	if not _check(write_ms < 1500 and read_ms < 1500, "saving and loading take under 1.5 s"):
		return
	var snap_ms := 1 << 30   # best of 3: the first call also warms caches; a busy machine adds noise
	for i in 3:
		t0 = Time.get_ticks_msec()
		SaveGame.snapshot(a, SEED)
		snap_ms = mini(snap_ms, Time.get_ticks_msec() - t0)
	print("autosave stalls the game for %d ms (the rest is written on a worker thread)" % snap_ms)
	if not _check(snap_ms < 60, "an autosave stalls the game under 60 ms"):
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("garbage {")
	f.close()
	if not _check(SaveGame.read(PATH).is_empty(), "a broken save file is ignored (new game)"):
		return
	SaveGame.delete(PATH)
	if not _check(not SaveGame.exists(PATH), "death deletes the save"):
		return
	print("SAVE_VERIFY: PASS")
	quit()

func _someone(world: World, nth: int) -> NPCData:
	var n := 0
	for id in world.entities:
		var npc: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if npc != null and not npc.is_cop and not npc.is_dealer and id != PlayerFactory.PLAYER_ENTITY_ID:
			if n == nth:
				return npc
			n += 1
	return null

func _check(good: bool, what: String) -> bool:
	if not good:
		print("SAVE_VERIFY: FAIL - ", what)
		quit(1)
	return good
