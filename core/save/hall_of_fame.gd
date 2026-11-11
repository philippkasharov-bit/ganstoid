## Hall of Fame (O1): every run that ends in death is written down. Records
## only: nothing carries over to the next run.
class_name HallOfFame
extends RefCounted

const PATH := "user://hall_of_fame.txt"

static func record(world: World, seed: int) -> void:
	var p: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var st: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var rules := GameRules.of(world)
	var runs := read()
	runs.append({"rank": st.rank, "rank_name": RankSystem.name_of(st.rank), "score": RankSystem.score(world, me, st),
		"days": float(world.tick) / SimClock.day_ticks, "cash": me.cash, "fame": st.fame, "traits": Traits.summary(st),
		"mode": "%s / %s" % [GameRules.DIFFICULTIES[rules.difficulty], GameRules.STYLES[rules.style]] if rules != null else "Normal", "seed": seed})
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(var_to_str(runs))

static func read() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var v: Variant = str_to_var(FileAccess.get_file_as_string(PATH))
	return v if v is Array else []

## The best runs, best first.
static func top(n: int) -> Array:
	var runs := read()
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return runs.slice(0, n)
