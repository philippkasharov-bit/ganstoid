## O1 validator: play styles change money, skills and needs by their
## multipliers; difficulty changes how fast a case builds; runs are written to
## the Hall of Fame and read back best first.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	var me := NPCData.new()
	me.id = PlayerFactory.PLAYER_ENTITY_ID
	var state := PlayerStateData.new()
	var p := Entity.new(me.id)
	p.add_component(me)
	p.add_component(state)
	world.register_entity(p)
	Wallet.earn_dirty(world, 100)
	var plain := me.cash
	GameRules.install(world, 2, 2)   # Hardcore / Grind
	Wallet.earn_dirty(world, 100)
	var grind := me.cash - plain
	Skills.train(world, state, &"melee", 25.0)
	var needs := NeedsSystem.new(world)
	var players := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	for t in SimClock.day_ticks / 2:
		needs.process_entities(players, 1.0 / SimClock.TICKS_PER_SECOND, t)
	print("no rules +$%d, grind +$%d; 25 melee XP -> level %d; half a day of grind: food %.2f; case per report x%.1f" % [plain, grind, Skills.level(state, &"melee"), me.hunger, GameRules.evidence(world)])
	if not _check(plain == 100 and grind == 200 and Skills.level(state, &"melee") == 1 and absf(me.hunger - (1.0 - 0.3 * 0.3)) < 0.02 and GameRules.evidence(world) == 1.4, "style and difficulty multipliers apply"):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HallOfFame.PATH))
	state.rank = 1
	HallOfFame.record(world, 1)
	state.rank = 4
	me.cash = 9000
	HallOfFame.record(world, 2)
	var top := HallOfFame.top(5)
	print("hall of fame: %d runs, best %s (%s)" % [top.size(), top[0]["rank_name"], top[0]["mode"]])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HallOfFame.PATH))
	if not _check(top.size() == 2 and top[0]["rank_name"] == "Boss" and top[0]["mode"] == "Hardcore / Grind", "runs are recorded, best first"):
		return
	print("PLAY_MODES_VERIFY: PASS")
	quit()

func _check(good: bool, what: String) -> bool:
	if not good:
		print("PLAY_MODES_VERIFY: FAIL - ", what)
		quit(1)
	return good
