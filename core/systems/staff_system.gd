## BZ2: people who work for you, by the day. Not crew: staff. Two jobs:
##   grower   looks after the grow at home while you're out (GrowSystem):
##            waters, feeds from the grow's stock, harvests, bags into the
##            grow's stash and replants from the stock; their skill counts
##            as yours for the stars
##   manager  runs a shop you own (BusinessSystem): its takings go up with
##            their skill
## Each one has a skill (shown as 1-5 stars, QL1), a daily wage (higher for
## the skilled) and an honesty you can only guess at ("straight", "hard to
## read", "shifty"). A shifty one skims: bags from the stash, dollars from
## the till. Wages go out each morning; can't pay, they quit. A grower who
## leaves unhappy knows where your grow is: they become a witness (CT1).
## Fire with severance (FIRE_DAYS of wages) and they go quietly.
## Candidates are ordinary people living near the place; their skill and
## honesty come from who they are (the same person always reads the same).
class_name StaffSystem
extends SystemBase

const EVERY := 60
const PHASE := 2
const ROLES := {"grower": "Grower", "manager": "Manager"}
const WAGE_BASE := 20
const WAGE_PER_SKILL := 60    # a top hand asks $80 a day
const CANDIDATES := 3
const CANDIDATE_R := 400.0    # they live this close to the place
const SKIM_BELOW := 0.5       # honesty under this and they take a cut
const MANAGER_BOOST := 0.4    # a top manager: +40% takings
const FIRE_DAYS := 3
const GRUDGE := -0.6          # how a grower who leaves badly feels about you

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _day := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	for p in entities.values():
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if not state.ui_biz.is_empty():
			var r := request(_world, me, state, state.ui_biz)
			state.ui_biz = {}
			StreetTalk.say(_world, state, r)
		var day := HustleSystem.day_of(tick)
		if day != _day:
			var first := _day == -1
			_day = day
			if not first:
				pay_day(_world, me, state)

## Phone > Business: {hire, at, role} or {fire}.
static func request(world: World, me: NPCData, state: PlayerStateData, ask: Dictionary) -> Dictionary:
	if ask.has("hire"):
		return hire(world, state, ask["hire"], ask.get("at", &""), String(ask.get("role", "")))
	if ask.has("fire"):
		return fire(world, me, state, ask["fire"])
	return {}

## What someone would be like at work: [skill 0..1, honesty 0..1].
static func traits_of(id: StringName) -> Vector2:
	var h := hash(String(id) + "staff")
	return Vector2(float(h % 1000) / 999.0, float((h / 1000) % 1000) / 999.0)

static func wage_of(skill: float) -> int:
	return WAGE_BASE + roundi(WAGE_PER_SKILL * skill)

static func stars(skill: float) -> int:
	return 1 + roundi(clampf(skill, 0.0, 1.0) * 4.0)

static func read_honesty(honesty: float) -> String:
	return "straight" if honesty >= 0.66 else ("hard to read" if honesty >= 0.33 else "shifty")

## The place a role works at is open: no one hired there yet.
static func open_at(state: PlayerStateData, at: StringName) -> bool:
	for id in state.staff:
		if state.staff[id].get("at", &"") == at:
			return false
	return true

## Up to CANDIDATES people near `where` who'd take the job.
static func candidates(world: World, state: PlayerStateData, where: Vector2) -> Array:
	var out: Array = []
	for id in world.spatial_index.query_nearby(where):
		var e: Entity = world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n == null or e.has_component(ComponentNames.PLAYER_STATE) or n.is_cop or n.is_crew or n.is_dealer or n.is_fixer or n.is_down or n.gang_id != &"":
			continue
		if state.staff.has(id) or MemorySystem.feel_of(state, id) < 0.0 or n.position.distance_to(where) > CANDIDATE_R:
			continue
		out.append(id)
		if out.size() >= CANDIDATES:
			break
	return out

static func hire(world: World, state: PlayerStateData, id: StringName, at: StringName, role: String) -> Dictionary:
	if not ROLES.has(role) or state.staff.has(id) or not open_at(state, at) or world.entities.get(id) == null:
		return {"ok": false, "reason": "staff_cant"}
	var t := traits_of(id)
	state.staff[id] = {"at": at, "role": role, "skill": t.x, "honesty": t.y, "wage": wage_of(t.x), "skimmed": 0}
	return {"ok": true, "effect": "staff_hired"}

static func fire(world: World, me: NPCData, state: PlayerStateData, id: StringName) -> Dictionary:
	var s: Dictionary = state.staff.get(id, {})
	if s.is_empty():
		return {"ok": false, "reason": "staff_cant"}
	var pay := int(s["wage"]) * FIRE_DAYS
	state.staff.erase(id)
	if me.cash >= pay:
		Wallet.spend(world, pay)
		return {"ok": true, "effect": "staff_fired", "amount": pay}
	_grudge(world, state, id, s)
	return {"ok": true, "effect": "staff_fired_angry"}

## Each morning: wages. Short, and they walk.
static func pay_day(world: World, me: NPCData, state: PlayerStateData) -> void:
	var paid := 0
	for id in state.staff.keys():
		var s: Dictionary = state.staff[id]
		if world.entities.get(id) == null:
			state.staff.erase(id)
			continue
		var wage := int(s["wage"])
		if me.cash >= wage:
			Wallet.spend(world, wage)
			paid += wage
		else:
			state.staff.erase(id)
			_grudge(world, state, id, s)
			PhoneSystem.push(world, state, _name(world, id), "No pay, no work. I'm done.")
	state.biz_day["wages"] = paid

## A grower who leaves badly knows where your grow is.
static func _grudge(world: World, state: PlayerStateData, id: StringName, s: Dictionary) -> void:
	if s.get("role", "") == "grower":
		state.memories[id] = {"deed": "saw_crime", "feel": GRUDGE, "day": SimClock.day_number(world.tick), "n": 1}

## The hired grower, or {}.
static func grower(state: PlayerStateData) -> Dictionary:
	for id in state.staff:
		if state.staff[id].get("role", "") == "grower":
			var s: Dictionary = state.staff[id]
			s["id"] = id
			return s
	return {}

## The manager of a shop, or {}.
static func manager_of(state: PlayerStateData, building_id: StringName) -> Dictionary:
	for id in state.staff:
		var s: Dictionary = state.staff[id]
		if s.get("role", "") == "manager" and s.get("at", &"") == building_id:
			return s
	return {}

## A shop's takings with its manager: up with skill, less what a shifty one keeps.
static func managed(state: PlayerStateData, building_id: StringName, take: int) -> int:
	var m := manager_of(state, building_id)
	if m.is_empty() or take <= 0:
		return take
	var up := int(take * (1.0 + MANAGER_BOOST * float(m["skill"])))
	var skim := skim_of(m, up)
	m["skimmed"] = int(m.get("skimmed", 0)) + skim
	return up - skim

## What a worker keeps for themselves out of `amount`.
static func skim_of(s: Dictionary, amount: int) -> int:
	var h := float(s.get("honesty", 1.0))
	return floori(amount * (SKIM_BELOW - h)) if h < SKIM_BELOW else 0

static func _name(world: World, id: StringName) -> String:
	var e: Entity = world.entities.get(id)
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	return n.display_name if n != null and n.display_name != "" else "Your worker"
