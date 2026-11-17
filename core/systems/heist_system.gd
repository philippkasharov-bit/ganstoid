## HS1: the big score. Every few game days (once you are a Hustler) word of a
## score reaches your phone: a jewellery store, a gang stash house, or an
## armoured van stopped at a corner for an hour. Then:
##   1 CASE IT    stand near it (CASE_M) for CASE_S: you learn how many guards
##                and what can go wrong, and the take goes up a quarter
##   2 THE JOB    in its window, E at the target: "Start the score". Stay within
##                WORK_M while the work runs; the alarm trips partway through
##                and the police come to the place (ST2: to the place, not you)
##   3 GETAWAY    get GETAWAY_M away with no police seeing you: the take is yours
## Your crew changes it: a lookout holds the alarm off longer, muscle makes the
## work quicker and takes on the guards, a driver means a shorter run. Each
## score rolls one complication. Down or arrested and it's lost. The pager and
## the phone's Score app show the plan; it all makes the paper. Saved (heist).
class_name HeistSystem
extends SystemBase

const PHASE := 41
const EVERY := 30
const OFFER_EVERY_DAYS := 2
const OFFER_HOUR := 9.0
const MIN_RANK := 1
const CASE_M := 35.0
const CASE_S := 25.0
const WORK_M := 8.0
const GETAWAY_M := 150.0
const DRIVER_GETAWAY_M := 90.0
const CASED_BONUS := 1.25
## kind -> [name, base take, work seconds, guards, min rank, window hours]
const KINDS := {
	"store": ["jewellery store", 900, 30.0, 1, 1, 6.0],
	"stash": ["gang stash house", 1400, 40.0, 3, 2, 8.0],
	"van": ["armoured van", 2200, 25.0, 2, 3, 1.0],
}
const COMPLICATIONS := {
	"quiet": "Nothing special. Don't get cocky.",
	"early_alarm": "The alarm is newer than you thought: it trips early.",
	"extra_guard": "One more guard than the word said.",
	"tough_safe": "The safe is tougher: the work takes longer.",
	"patrol": "A patrol car is round the corner: the police come fast.",
}

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	var step := float(EVERY) / SimClock.TICKS_PER_SECOND
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if state.heist.is_empty():
			_maybe_offer(state, me, tick)
		else:
			advance(_world, state, me, tick, step)

## Word of a score, every OFFER_EVERY_DAYS game days from the morning.
func _maybe_offer(state: PlayerStateData, me: NPCData, tick: int) -> void:
	var day := HustleSystem.day_of(tick)
	if state.rank < MIN_RANK or day - state.heist_day < OFFER_EVERY_DAYS or SimClock.day_fraction(tick) * 24.0 < OFFER_HOUR:
		return
	if offer(_world, state, me, tick):
		state.heist_day = day

## Picks the best score your rank allows and sends the word. False if none fits.
static func offer(world: World, state: PlayerStateData, me: NPCData, tick: int, only: String = "") -> bool:
	var rng := world.runtime_rng
	var kinds: Array = []
	for k in KINDS:
		if (only == "" and state.rank >= int(KINDS[k][4])) or k == only:
			kinds.append(k)
	kinds.shuffle()
	for kind in kinds:
		var spot := _target(world, kind, me.position, rng)
		if spot.is_empty():
			continue
		var spec: Array = KINDS[kind]
		var start := tick + SimClock.hours(rng.randf_range(2.0, 6.0))
		var comp: String = COMPLICATIONS.keys()[rng.randi() % COMPLICATIONS.size()]
		state.heist = {"kind": kind, "at": spot["at"], "target": spot.get("id", &""), "where": spot["where"],
			"take": int(spec[1] * rng.randf_range(0.85, 1.2)), "guards": int(spec[3]) + (1 if comp == "extra_guard" else 0),
			"complication": comp, "stage": "rumour", "cased": 0.0, "known": false,
			"from": start, "until": start + SimClock.hours(float(spec[5])), "work": 0.0, "alarm": false}
		PhoneSystem.push(world, state, "Fixer", "Word on a score: a %s %s. Worth about $%d. Go look at it first. It's on between %s." % [spec[0], spot["where"], state.heist["take"], window_text(state.heist)])
		StampView.put(state, "A SCORE", "%s: check your phone" % String(spec[0]).to_upper())
		if state.waypoint == Vector2.INF:
			state.waypoint = spot["at"]
		return true
	return false

static func _target(world: World, kind: String, near: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var options: Array = []
	match kind:
		"store", "stash":
			for e in world.get_entities_with_component(ComponentNames.BUILDING).values():
				var b: BuildingData = e.get_component(ComponentNames.BUILDING)
				var d := b.position.distance_to(near)
				if d < 150.0 or d > 900.0 or BusinessSystem.owned_by_player(b):
					continue
				if kind == "store" and b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
					options.append(b)
				elif kind == "stash" and b.building_type != GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.building_type != GanstoidEnums.BuildingType.RESIDENCE and _gang_of(world, b.id) != &"":
					options.append(b)
			if options.is_empty():
				return {}
			var b: BuildingData = options[rng.randi() % options.size()]
			return {"at": b.position, "id": b.id, "where": "on " + _street(b.position)}
		"van":
			var at := near + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(300.0, 700.0)
			if SimNav.active != null:
				at = SimNav.active.snap(at, "public")
			return {"at": at, "where": "stopped on " + _street(at)}
	return {}

static func _gang_of(world: World, building: StringName) -> StringName:
	for e in world.get_entities_with_component(ComponentNames.GANG).values():
		var g: GangData = e.get_component(ComponentNames.GANG)
		if g.territory_building_ids.has(building):
			return g.id
	return &""

static func _street(at: Vector2) -> String:
	var h := Hoods.data()
	return h.name_of(TerritoryData.turf_of(at)) if h != null else "the block"

static func window_text(h: Dictionary) -> String:
	var a := SimClock.day_fraction(int(h["from"])) * 24.0
	var b := SimClock.day_fraction(int(h["until"])) * 24.0
	return "%02d:00 and %02d:00" % [int(a), int(b) % 24]

## One step of the score you are on.
static func advance(world: World, state: PlayerStateData, me: NPCData, tick: int, step: float) -> void:
	var h := state.heist
	var at: Vector2 = h["at"]
	var d := me.position.distance_to(at)
	if me.is_down:
		_fail(world, state, "You went down. The take is gone.")
		return
	match String(h["stage"]):
		"rumour", "cased":
			if h["stage"] == "rumour" and d <= CASE_M:
				h["cased"] = float(h["cased"]) + step
				if float(h["cased"]) >= CASE_S:
					h["stage"] = "cased"
					h["known"] = true
					h["take"] = int(float(h["take"]) * CASED_BONUS)
					PhoneSystem.push(world, state, "You", "Cased the %s. %d guards. %s Take now about $%d." % [KINDS[h["kind"]][0], int(h["guards"]), COMPLICATIONS[h["complication"]], int(h["take"])])
					StampView.put(state, "CASED", "%d guards · %s" % [int(h["guards"]), String(h["complication"]).replace("_", " ")])
			if tick > int(h["until"]):
				_fail(world, state, "The %s is gone. Too late." % KINDS[h["kind"]][0])
		"working":
			if d > WORK_M:
				_fail(world, state, "You walked off the job.")
				return
			var speed := 1.0 + 0.4 * _crew(world, state, GanstoidEnums.CrewRole.MUSCLE)
			if h["complication"] == "tough_safe":
				speed *= 0.65
			h["work"] = float(h["work"]) + step * speed
			var need: float = KINDS[h["kind"]][2]
			var alarm_at := need * (0.3 if h["complication"] == "early_alarm" else 0.55) * (1.0 + 0.5 * _crew(world, state, GanstoidEnums.CrewRole.LOOKOUT))
			if not h["alarm"] and float(h["work"]) >= alarm_at:
				h["alarm"] = true
				_alarm(world, state, at, h)
			if float(h["work"]) >= need:
				h["stage"] = "getaway"
				StampView.put(state, "GOT IT", "now get away: %d m, unseen" % int(getaway_m(world, state)))
		"getaway":
			if d >= getaway_m(world, state) and not _seen_by_police(world, me):
				var take := int(h["take"])
				Wallet.earn_dirty(world, take)
				Rep.add(state, 15.0)
				NewsSystem.note_story(state, "heist_" + String(h["kind"]), "$%d" % take, at)
				PhoneSystem.push(world, state, "Fixer", "Clean. $%d. People will talk about this one." % take)
				StampView.put(state, "SCORE!", "+$%d" % take, UiTheme.GOOD)
				_end(state, at)

## E at the target in its window: the job starts.
static func start(world: World, state: PlayerStateData, me: NPCData) -> Dictionary:
	var h := state.heist
	if h.is_empty() or not (h["stage"] in ["rumour", "cased"]):
		return {"ok": false, "reason": "no_heist"}
	if me.position.distance_to(h["at"]) > WORK_M:
		return {"ok": false, "reason": "too_far"}
	if world.tick < int(h["from"]):
		return {"ok": false, "reason": "heist_not_yet"}
	h["stage"] = "working"
	h["work"] = 0.0
	var combat := world.find_system(NPCCombatSystem) as NPCCombatSystem
	var guards := maxi(0, int(h["guards"]) - _crew(world, state, GanstoidEnums.CrewRole.MUSCLE))
	if combat != null and guards > 0:
		var g := _gang_of(world, h.get("target", &"")) if h["kind"] == "stash" else &""
		if g != &"":
			combat.send_squad(g, guards, world.tick)
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.ARMED_ROBBERY])
	return {"ok": true, "effect": "heist_started"}

static func _alarm(world: World, state: PlayerStateData, at: Vector2, h: Dictionary) -> void:
	var cops := world.find_system(CopAISystem) as CopAISystem
	if cops != null:
		cops.on_crime_witnessed(GanstoidEvents.CRIME_WITNESSED, {"position": at})
		if h["complication"] == "patrol":
			cops.on_crime_witnessed(GanstoidEvents.CRIME_WITNESSED, {"position": at})
	if state.law_tier == GanstoidEnums.LawTier.CLEAN:
		state.law_tier = GanstoidEnums.LawTier.WARNED
	StampView.put(state, "ALARM!", "finish it or run", UiTheme.BAD)

static func getaway_m(world: World, state: PlayerStateData) -> float:
	return DRIVER_GETAWAY_M if _crew(world, state, GanstoidEnums.CrewRole.DRIVER) > 0 else GETAWAY_M

## How many of your crew have this role.
static func _crew(world: World, state: PlayerStateData, role: int) -> int:
	var n := 0
	for id in state.crew_ids:
		var e: Entity = world.entities.get(id)
		var c: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		n += int(c != null and not c.is_down and c.crew_role == role)
	return n

static func _seen_by_police(world: World, me: NPCData) -> bool:
	for id in world.spatial_index.query_nearby(me.position):
		var e: Entity = world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and n.is_cop and not n.is_down and CrimeSystem.can_see(world, n.position, me.position, true):
			return true
	var traffic := world.find_system(TrafficSystem) as TrafficSystem
	return traffic != null and traffic.chasing()

static func _fail(world: World, state: PlayerStateData, why: String) -> void:
	PhoneSystem.push(world, state, "Fixer", why)
	StampView.put(state, "SCORE BLOWN", why, UiTheme.BAD)
	_end(state, state.heist.get("at", Vector2.INF))

static func _end(state: PlayerStateData, at: Vector2) -> void:
	if state.waypoint != Vector2.INF and at != Vector2.INF and state.waypoint.distance_to(at) < 1.0:
		state.waypoint = Vector2.INF
	state.heist = {}

## For the pager and the phone: what to do now.
static func plan_line(world: World, state: PlayerStateData) -> String:
	var h := state.heist
	if h.is_empty():
		return ""
	var name: String = KINDS[h["kind"]][0]
	match String(h["stage"]):
		"rumour":
			return "Score: case the %s %s (stand near it %ds)" % [name, h["where"], int(CASE_S)]
		"cased":
			return "Score: the %s, %s. E there to start ($%d)" % [name, window_text(h), int(h["take"])]
		"working":
			return "Score: stay close! %d%%%s" % [int(100.0 * float(h["work"]) / float(KINDS[h["kind"]][2])), "  ALARM" if h["alarm"] else ""]
		"getaway":
			return "Score: get %d m away, unseen" % int(getaway_m(world, state))
	return ""
