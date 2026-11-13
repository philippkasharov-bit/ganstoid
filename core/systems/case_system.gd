## Investigation, lying low, court and prison (I1 + LL1 + CP1).
## Only what witnesses report builds a case against you (the evidence gate
## stays the one door): each CRIME_WITNESSED adds severity * EVIDENCE_PER.
##   - Lying low: the case goes cold by itself, faster while you sit at home.
##   - Warrant: a case of WARRANT_AT or more and any cop who sees you comes for you.
##   - Arrest -> court: a weak case is a night in the cells (old behaviour);
##     otherwise DAYS_PER evidence buys days inside: the world runs on fast
##     while you serve, dirty money, drugs and guns are taken, crew loyalty
##     slips; you walk out at home with a clean slate.
##   - A lawyer (E, any time) knocks LAWYER_CUT off the case for LAWYER_FEE clean.
class_name CaseSystem
extends SystemBase

const EVIDENCE_PER := 20.0
const COLD_PER_HOUR := 1.5
const COLD_AT_HOME_PER_HOUR := 4.0
const WARRANT_AT := 40.0
const PRISON_FROM := 20.0
const DAYS_PER := 20.0
const MAX_DAYS := 7
const LAWYER_FEE := 500
const LAWYER_CUT := 30.0
const SIGHT_CHECK_TICKS := 30

var _last_hour := -1
const PHASE_TICKS := 47
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func on_crime_witnessed(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.CRIME_WITNESSED:
		return
	for p in _world.get_entities_with_component(ComponentNames.PLAYER_STATE).values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var sev := float(payload.get("severity", 0.0))
		if Traits.has(state, &"dealer") and is_equal_approx(sev, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED]):
			sev *= 1.5   # T1 Plug: they know what you do
		state.case_evidence += sev * EVIDENCE_PER * GameRules.evidence(_world)   # O1

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	for p in entities.values():
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.prison_until_tick > 0:
			if tick >= state.prison_until_tick:
				_release(me, state)
			continue
		var hour := (tick - PHASE_TICKS) / SimClock.hours(1.0)   # PF1: staggered from the other hourly jobs
		if hour != _last_hour:
			_last_hour = hour
			var home: bool = state.sleeping and state.sleeping_home or _at_home(me)
			state.case_evidence = maxf(0.0, state.case_evidence - (COLD_AT_HOME_PER_HOUR if home else COLD_PER_HOUR))
			state.fame = maxf(0.0, state.fame - Traits.FAME_FADE_PER_HOUR)   # F1
		if state.case_evidence >= WARRANT_AT and tick % SIGHT_CHECK_TICKS == 0:
			_cops_on_the_lookout(me)

## Warrant out: a cop who can see you knows your face from the file.
func _cops_on_the_lookout(me: NPCData) -> void:
	var cops := _world.find_system(CopAISystem) as CopAISystem
	if cops == null:
		return
	for id in _world.spatial_index.query_nearby(me.position):
		var e: Entity = _world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and n.is_cop and not n.is_down and CrimeSystem.can_see(_world, n.position, me.position):
			cops.alert(id)

func _at_home(me: NPCData) -> bool:
	var home: Entity = _world.entities.get(me.home_building_id)
	return home != null and home.get_component(ComponentNames.BUILDING).position.distance_to(me.position) <= NeedsSystem.BED_M

## Court, on arrest. Returns the days given (0 = a night in the cells).
static func sentence(world: World, me: NPCData, state: PlayerStateData) -> int:
	if state.case_evidence < PRISON_FROM:
		state.case_evidence = 0.0
		return 0
	var days := clampi(roundi(state.case_evidence / DAYS_PER), 1, MAX_DAYS)
	state.prison_until_tick = world.tick + days * SimClock.day_ticks
	Wallet.seize_dirty(world, 1.0)   # all dirty money goes into evidence
	for id in state.inventory.keys():
		var it := ItemCatalog.item(id)
		if it.is_empty() or it["kind"] == "weapon":
			state.inventory.erase(id)   # drugs and guns go into evidence
	state.ammo = 0
	state.weapon = &"fists"
	state.vehicle_id = &""
	state.job = {}
	me.indoors = true
	world.spatial_index.remove(me.id)   # inside: nobody on the street meets you
	return days

func _release(me: NPCData, state: PlayerStateData) -> void:
	state.prison_until_tick = 0
	state.case_evidence = 0.0
	state.law_tier = GanstoidEnums.LawTier.CLEAN
	me.indoors = false
	me.hunger = 0.7
	me.thirst = 0.7
	var home: Entity = _world.entities.get(me.home_building_id)
	if home != null:
		me.position = home.get_component(ComponentNames.BUILDING).position
	_world.reindex_position(me.id)
	StreetTalk.say_key(_world, state, "released")

static func lawyer(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	if state.case_evidence <= 0.0:
		return {"ok": false, "reason": "no_case"}
	if Wallet.clean(world) < LAWYER_FEE:
		return {"ok": false, "reason": "need_clean_cash"}
	Wallet.spend_clean(world, LAWYER_FEE)
	state.case_evidence = maxf(0.0, state.case_evidence - LAWYER_CUT)
	return {"ok": true, "effect": "lawyer", "amount": LAWYER_FEE}
