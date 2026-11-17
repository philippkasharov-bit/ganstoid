## CT1: your day in court. An arrest with a real case (CaseSystem.PRISON_FROM
## or more) no longer sends you straight inside: you are charged, searched
## (dirty cash, drugs and guns kept as evidence) and let out to wait
## TRIAL_DAYS for the trial. The witnesses are the people who remember you
## badly (ME1's memories: robbed, hurt, threatened, saw you at it). Before
## the trial you can work on them:
##   scare one       fear SCARED_AT or more: they don't show up
##   pay one off     feel BOUGHT_AT or better: "I don't remember anything"
##   a lawyer        each hire knocks LAWYER_CUT off the case
##   (a dead witness says nothing, but killing is a crime of its own)
## On the day the court sits: the case on file plus each witness who talks
## (the angrier, the worse) against GUILTY_AT. Guilty: CaseSystem.sentence
## gives the days. The court window (CourtWindow) shows who said what.
class_name CourtSystem
extends SystemBase

const EVERY := 60
const PHASE := 31
const TRIAL_DAYS := 2.0
const MAX_WITNESSES := 6
const WITNESS_DEEDS := ["robbed", "hurt", "threatened", "caught_lifting", "saw_crime", "store_robbed"]
const SCARED_AT := 0.6       # this afraid of you: they stay home
const BOUGHT_AT := -0.1      # feel this good or better: they forget
const FILE_WEIGHT := 0.5     # how much the evidence on file counts in court
const WITNESS_PTS := 30.0    # a witness at full anger adds this
const GUILTY_AT := 30.0
const LAWYER_FEE := 500
const LAWYER_CUT := 25.0
const SAYS := {
	"robbed": "\"That's the one. A knife in my face, and my money gone.\"",
	"hurt": "\"They beat me. I still can't sleep.\"",
	"threatened": "\"They threatened me. I'm still telling you.\"",
	"caught_lifting": "\"Their hand was in my pocket.\"",
	"saw_crime": "\"I saw it. That's the one.\"",
	"store_robbed": "\"They held up my store.\"",
}

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

## On arrest: charge and let out to wait for the trial. False when the case is
## too thin to try (the old night in the cells).
static func charge(world: World, me: NPCData, state: PlayerStateData) -> bool:
	if state.case_evidence < CaseSystem.PRISON_FROM and state.trial.is_empty():
		return false
	var file := state.case_evidence + float(state.trial.get("evidence", 0.0))
	Wallet.seize_dirty(world, 0.5 if state.crib >= CribSystem.SAFE_TIER else 1.0)   # searched: into evidence (CR1: the safe at home keeps half)
	for id in state.inventory.keys():
		var it := ItemCatalog.item(id)
		if it.is_empty() or it["kind"] == "weapon":
			state.inventory.erase(id)
	state.ammo = 0
	state.weapon = &"fists"
	state.case_evidence = 0.0
	var again := not state.trial.is_empty()   # arrested while out on bail: tried at once
	state.trial = {"at": world.tick + (0 if again else int(TRIAL_DAYS * SimClock.day_ticks)), "evidence": file,
		"witnesses": witnesses(world, state), "lawyer": float(state.trial.get("lawyer", 0.0))}
	if not again:
		var n: int = state.trial["witnesses"].size()
		PhoneSystem.push(world, state, "Public defender", "You're charged. Trial in %d days. %d witness%s against you. Phone > Case." % [int(TRIAL_DAYS), n, "" if n == 1 else "es"])
		StampView.put(state, "CHARGED", "trial in %d days · %d witnesses" % [int(TRIAL_DAYS), n], UiTheme.BAD)
	return true

## The people who'd speak against you: worst feeling first.
static func witnesses(world: World, state: PlayerStateData) -> Array:
	var out: Array = []
	for id in state.memories:
		var m: Variant = state.memories[id]
		if m is Dictionary and WITNESS_DEEDS.has(m.get("deed", "")) and float(m.get("feel", 0.0)) < 0.0:
			var e: Entity = world.entities.get(id)
			if e != null and e.get_component(ComponentNames.NPC) != null:
				out.append(id)
	out.sort_custom(func(a: Variant, b: Variant) -> bool: return MemorySystem.feel_of(state, a) < MemorySystem.feel_of(state, b))
	return out.slice(0, MAX_WITNESSES)

## What a witness will do on the day: "talks", "scared", "bought", "dead" or "gone".
static func stand_of(world: World, state: PlayerStateData, id: StringName) -> String:
	var e: Entity = world.entities.get(id)
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	if n == null:
		return "gone"
	if n.is_down and n.health <= 0.0:
		return "dead"
	if n.fear >= SCARED_AT:
		return "scared"
	if not state.memories.has(id) or MemorySystem.feel_of(state, id) >= BOUGHT_AT:
		return "bought"
	return "talks"

## The case as it stands: the file plus each witness who talks, minus the lawyer.
static func score(world: World, state: PlayerStateData) -> float:
	var s := float(state.trial.get("evidence", 0.0)) * FILE_WEIGHT - float(state.trial.get("lawyer", 0.0))
	for id in state.trial.get("witnesses", []):
		if stand_of(world, state, id) == "talks":
			s += WITNESS_PTS * clampf(-MemorySystem.feel_of(state, id), 0.3, 1.0)
	return maxf(0.0, s)

## Hire (more) lawyer for the trial.
static func lawyer(world: World, state: PlayerStateData) -> Dictionary:
	if state.trial.is_empty():
		return {"ok": false, "reason": "no_case"}
	if Wallet.clean(world) < LAWYER_FEE:
		return {"ok": false, "reason": "need_clean_cash"}
	Wallet.spend_clean(world, LAWYER_FEE)
	state.trial["lawyer"] = float(state.trial.get("lawyer", 0.0)) + LAWYER_CUT
	return {"ok": true, "effect": "lawyer", "amount": LAWYER_FEE}

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	for p in entities.values():
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.ui_court == "close":
			state.ui_court = ""
			state.verdict = {}
		if state.trial.is_empty() or state.prison_until_tick > 0:
			continue
		if not (state.trial.get("at") is int and state.trial.get("witnesses") is Array):
			state.trial = {}   # a broken save: no trial
			continue
		if tick >= int(state.trial["at"]):
			hold(_world, me, state)

## The court sits: who says what, then the verdict.
static func hold(world: World, me: NPCData, state: PlayerStateData) -> void:
	var lines: Array = []
	for id in state.trial["witnesses"]:
		var e: Entity = world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		var who: String = n.display_name if n != null and n.display_name != "" else "A witness"
		var m: Dictionary = state.memories.get(id, {})
		match stand_of(world, state, id):
			"talks": lines.append([who, SAYS.get(m.get("deed", ""), SAYS["saw_crime"]), -1])
			"scared": lines.append([who, "didn't show up. Too scared.", 1])
			"bought": lines.append([who, "\"I... don't remember anything.\"", 1])
			"dead": lines.append([who, "can't testify. Dead.", 0])
			_: lines.append([who, "couldn't be found.", 1])
	var s := score(world, state)
	var lawyer_cut := float(state.trial.get("lawyer", 0.0))
	state.trial = {}
	var days := 0
	if s >= GUILTY_AT:
		state.case_evidence = maxf(s, CaseSystem.PRISON_FROM)
		days = CaseSystem.sentence(world, me, state)
		StampView.put(state, "GUILTY", "%d day%s inside" % [days, "" if days == 1 else "s"], UiTheme.BAD)
	else:
		StampView.put(state, "NOT GUILTY", "you walk out the front door", UiTheme.GOOD)
	state.verdict = {"lines": lines, "guilty": days > 0, "days": days, "score": s, "lawyer": lawyer_cut}
	StreetTalk._count(world, state, "verdict_guilty" if days > 0 else "verdict_free", days)
