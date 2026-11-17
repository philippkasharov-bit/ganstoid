## RP3: join a gang and rise in it, instead of only fighting them.
##   JOIN    E by one of a gang's people, on their turf: "Ask to join". They
##           take you if you're in good with them (standing JOIN_STANDING:
##           deals, gun sales, gang jobs), known on the street (Rep Known),
##           and their lieutenant isn't after you.
##   RANKS   Prospect, Soldier, Shot-caller, Lieutenant: gang rep from the
##           missions they give you (two a day on the phone's Gang app):
##           tag their rivals' blocks, move product, hurt a rival gang's
##           people, collect tax on one of their corners.
##   PERKS   their corners treat you as family (no warnings), the other
##           gangs hold it against you (a grudge on joining), and every
##           morning you get a cut of the gang's money that grows with rank.
##           At Lieutenant you run their corners: the old one steps aside.
##   LEAVE   on the phone; they don't forget (their lieutenant's grudge).
## Saved: gang_member, gang_rank, gang_rep, gang_missions.
class_name GangLifeSystem
extends SystemBase

const PHASE := 59
const JOIN_STANDING := 0.6
const JOIN_REP := 1
const RANKS := ["Prospect", "Soldier", "Shot-caller", "Lieutenant"]
const RANK_AT := [0, 30, 80, 160]
const CUT := [0.0, 0.02, 0.04, 0.08]        # of the gang's cash each morning
const OTHERS_GRUDGE := 20.0
const LEAVE_GRUDGE := 60.0
const TAX_S := 20.0
const PER_DAY := 2
## kind -> [text, result keys that count, how many, gang rep, pay]
const MISSIONS := {
	"tag": ["Tag %d of the other gangs' blocks", ["tag_rival"], 2, 12, 60],
	"sell": ["Move %d bags for the gang", ["sell"], 3, 10, 90],
	"hit": ["Hurt %d of a rival gang's people", ["hit_rival"], 2, 15, 80],
	"tax": ["Collect tax on %d of our corners (stand there 20 s)", ["tax"], 1, 10, 70],
}

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _tax_s := 0.0

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if state.ui_gang != "":
			var ask := state.ui_gang
			state.ui_gang = ""
			if ask == "leave":
				StreetTalk.say(_world, state, leave(_world, state))
		if state.gang_member == &"" or tick % SimClock.TICKS_PER_SECOND != PHASE:
			continue
		var day := HustleSystem.day_of(tick)
		if state.gang_day != day:
			state.gang_day = day
			_morning(state, day)
		_tax(state, me)

## E by a gang's person on their turf.
static func join(world: World, state: PlayerStateData, gang: StringName) -> Dictionary:
	if state.gang_member != &"":
		return {"ok": false, "reason": "gang_already"}
	var t := TerritorySystem.data(world)
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if t == null or TerritorySystem.controller(t, TerritoryData.turf_of(me.position)) != gang:
		return {"ok": false, "reason": "gang_not_here"}
	if float(state.gang_standing.get(gang, 0.5)) < JOIN_STANDING:
		return {"ok": false, "reason": "gang_standing"}
	if Rep.tier(state) < JOIN_REP:
		return {"ok": false, "reason": "gang_unknown"}
	if float(state.rivals.get(gang, {}).get("grudge", 0.0)) >= RivalSystem.THREAT:
		return {"ok": false, "reason": "gang_grudge"}
	state.gang_member = gang
	state.gang_rank = 0
	state.gang_rep = 0
	state.gang_missions = []
	state.gang_day = -1000000
	for g in state.rivals:
		if g != gang:
			RivalSystem.grow(world, state, g, OTHERS_GRUDGE)   # the others hold it against you
	StampView.put(state, "JUMPED IN", "%s: Prospect" % gang_name(world, gang), UiTheme.GOOD)
	return {"ok": true, "effect": "gang_joined"}

static func leave(world: World, state: PlayerStateData) -> Dictionary:
	if state.gang_member == &"":
		return {"ok": false, "reason": "gang_none"}
	var g := state.gang_member
	state.gang_member = &""
	state.gang_rank = 0
	state.gang_missions = []
	state.gang_standing[g] = 0.2
	RivalSystem.ensure(world, state)
	RivalSystem.grow(world, state, g, LEAVE_GRUDGE)
	return {"ok": true, "effect": "gang_left"}

func _morning(state: PlayerStateData, day: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("gang" + str(day))
	var kinds := MISSIONS.keys()
	state.gang_missions = []
	while state.gang_missions.size() < PER_DAY:
		var k: String = kinds.pop_at(rng.randi() % kinds.size())
		state.gang_missions.append({"kind": k, "got": 0, "need": MISSIONS[k][2], "done": false})
	var e: Entity = _world.entities.get(state.gang_member)
	var g: GangData = e.get_component(ComponentNames.GANG) if e != null else null
	if g != null and state.gang_rank > 0:
		var cut := int(g.cash * CUT[state.gang_rank])
		if cut > 0:
			g.cash -= cut
			Wallet.earn_dirty(_world, cut)
			PhoneSystem.push(_world, state, gang_name(_world, state.gang_member), "Your cut: $%d." % cut)
	PhoneSystem.push(_world, state, gang_name(_world, state.gang_member), "Today: " + " · ".join(state.gang_missions.map(func(m: Dictionary) -> String: return mission_text(m))))

## A result came in (StreetTalk, combat): moves the gang's missions.
static func progress(world: World, state: PlayerStateData, key: String) -> void:
	if state.gang_member == &"":
		return
	if key == "tagged":
		var t := TerritorySystem.data(world)
		var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
		var owner := TerritorySystem.controller(t, TerritoryData.turf_of(me.position)) if t != null else &""
		if owner == &"" or owner == TerritorySystem.PLAYER or owner == state.gang_member:
			return
		key = "tag_rival"
	for m in state.gang_missions:
		if m["done"] or not (MISSIONS[m["kind"]][1] as Array).has(key):
			continue
		m["got"] = int(m["got"]) + 1
		if int(m["got"]) >= int(m["need"]):
			m["done"] = true
			var spec: Array = MISSIONS[m["kind"]]
			state.gang_rep += int(spec[3])
			Wallet.earn_dirty(world, int(spec[4]))
			StampView.put(state, "FOR THE SET", "%s  +$%d" % [mission_text(m), int(spec[4])], UiTheme.GOOD)
			_promote(world, state)
		return

static func _promote(world: World, state: PlayerStateData) -> void:
	var r := 0
	for i in RANK_AT.size():
		if state.gang_rep >= RANK_AT[i]:
			r = i
	if r <= state.gang_rank:
		return
	state.gang_rank = r
	StampView.put(state, RANKS[r].to_upper(), "in %s" % gang_name(world, state.gang_member), UiTheme.GOOD)
	if r == RANKS.size() - 1 and state.rivals.has(state.gang_member):
		state.rivals.erase(state.gang_member)   # you run their corners now: the old lieutenant steps aside
		PhoneSystem.push(world, state, gang_name(world, state.gang_member), "The corners are yours now. Don't make us regret it.")

## Standing on one of your gang's corners collects its tax (a mission).
func _tax(state: PlayerStateData, me: NPCData) -> void:
	var t := TerritorySystem.data(_world)
	if t == null or TerritorySystem.controller(t, TerritoryData.turf_of(me.position)) != state.gang_member:
		_tax_s = 0.0
		return
	_tax_s += 1.0
	if _tax_s >= TAX_S:
		_tax_s = 0.0
		progress(_world, state, "tax")

## A rival gang's person hurt by you (CombatSystem's ASSAULTED).
func on_assaulted(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.ASSAULTED:
		return
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var e: Entity = _world.entities.get(payload.get("victim_id", &""))
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	if p == null or n == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	if state.gang_member != &"" and n.gang_id != &"" and n.gang_id != state.gang_member:
		progress(_world, state, "hit_rival")

static func mission_text(m: Dictionary) -> String:
	var t: String = MISSIONS[m["kind"]][0]
	return (t % int(m["need"])) + ("  DONE" if m["done"] else "  %d/%d" % [int(m["got"]), int(m["need"])])

static func gang_name(world: World, g: StringName) -> String:
	var e: Entity = world.entities.get(g)
	return e.get_component(ComponentNames.GANG).display_name if e != null else String(g)
