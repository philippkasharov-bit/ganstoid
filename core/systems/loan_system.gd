## BZ5: loan sharking. Each morning a few people near you who are short
## ask for money (Phone > Loans): an amount and the interest they'll pay
## over TERM_DAYS. Lend, and they pay it back day by day out of their own
## pocket, if they can and if they're the paying kind (some aren't).
## Late? Find them (E by them):
##   collect        whatever cash they have, towards the debt
##   lean on them   a threat: they're scared, they pay double from now on
##   make an example a beating: the debt is written off, everyone else who
##                  owes you pays on time from then on, and it's a crime
## Interest comes in as dirty money. Lending is from your cash.
class_name LoanSystem
extends SystemBase

const EVERY := 60
const PHASE := 5
const ASKS_A_DAY := 2
const ASK_R := 350.0
const AMOUNTS := [100, 200, 300, 500, 800]
const RATE := Vector2(0.2, 0.45)
const TERM_DAYS := 7
const SCARED_PAY := 2.0
const EXAMPLE_FEAR := 0.35          # other debtors' reliability after you make an example
const MAX_LOANS := 8

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
		if not state.ui_loan.is_empty():
			StreetTalk.say(_world, state, lend(_world, me, state, int(state.ui_loan.get("ask", -1))))
			state.ui_loan = {}
		var day := HustleSystem.day_of(tick)
		if day != _day:
			var first := _day == -1
			_day = day
			if not first:
				new_day(_world, me, state, day)

## How reliably someone pays (the same person always the same), 0..1.
static func reliability(id: StringName) -> float:
	return float(hash(String(id) + "pays") % 1000) / 999.0

## Each morning: payments come in, late ones are marked, new people ask.
static func new_day(world: World, me: NPCData, state: PlayerStateData, day: int) -> void:
	var rng := world.runtime_rng
	var paid_today := 0
	for loan in state.loans:
		if int(loan["owed"]) <= 0:
			continue
		var e: Entity = world.entities.get(loan["who"])
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n == null or (n.is_down and n.health <= 0.0):
			loan["owed"] = 0
			loan["status"] = "lost"
			continue
		var due := ceili(float(loan["total"]) / TERM_DAYS) * (SCARED_PAY if loan.get("scared", false) else 1.0)
		var willing := maxf(reliability(loan["who"]), float(loan.get("fear", 0.0)))
		if rng.randf() < willing:
			var pay := mini(int(due), int(loan["owed"]))
			Wallet.earn_dirty(world, pay)
			paid_today += pay
			loan["owed"] = int(loan["owed"]) - pay
			loan["paid"] = int(loan.get("paid", 0)) + pay
			loan["status"] = "paid off" if int(loan["owed"]) <= 0 else "paying"
		elif day >= int(loan["due"]):
			loan["status"] = "late"
		else:
			loan["status"] = "missed a day"
	state.biz_day["loans"] = paid_today   # BZ7: the Empire page
	state.loans = state.loans.filter(func(l: Dictionary) -> bool: return int(l["owed"]) > 0 or day - int(l["day"]) < TERM_DAYS + 3)
	state.loan_asks = []
	if state.loans.filter(func(l: Dictionary) -> bool: return int(l["owed"]) > 0).size() >= MAX_LOANS:
		return
	for id in world.spatial_index.query_nearby(me.position):
		if state.loan_asks.size() >= ASKS_A_DAY:
			break
		var e: Entity = world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n == null or e.has_component(ComponentNames.PLAYER_STATE) or n.is_cop or n.is_crew or n.is_dealer or n.is_down or n.gang_id != &"":
			continue
		if n.position.distance_to(me.position) > ASK_R or owes(state, id) or rng.randf() > 0.15:
			continue
		state.loan_asks.append({"who": id, "amount": AMOUNTS[rng.randi() % AMOUNTS.size()], "rate": snappedf(rng.randf_range(RATE.x, RATE.y), 0.05)})

static func owes(state: PlayerStateData, id: StringName) -> bool:
	return state.loans.any(func(l: Dictionary) -> bool: return l["who"] == id and int(l["owed"]) > 0)

static func loan_of(state: PlayerStateData, id: StringName) -> Dictionary:
	for l in state.loans:
		if l["who"] == id and int(l["owed"]) > 0:
			return l
	return {}

## Phone: take up ask number `i`.
static func lend(world: World, me: NPCData, state: PlayerStateData, i: int) -> Dictionary:
	if i < 0 or i >= state.loan_asks.size():
		return {}
	var a: Dictionary = state.loan_asks[i]
	if me.cash < int(a["amount"]):
		return {"ok": false, "reason": "cant_afford"}
	Wallet.spend(world, int(a["amount"]))
	var total := roundi(int(a["amount"]) * (1.0 + float(a["rate"])))
	var day := HustleSystem.day_of(world.tick)
	state.loans.append({"who": a["who"], "principal": int(a["amount"]), "total": total, "owed": total, "paid": 0, "day": day, "due": day + TERM_DAYS, "status": "new"})
	state.loan_asks.remove_at(i)
	return {"ok": true, "effect": "loan_out", "amount": int(a["amount"])}

## E by someone who owes you: they hand over what they have.
static func collect(world: World, state: PlayerStateData, n: NPCData) -> Dictionary:
	var loan := loan_of(state, n.id)
	if loan.is_empty():
		return {"ok": false, "reason": "nothing_to_take"}
	var pay := mini(n.cash, int(loan["owed"]))
	if pay <= 0:
		return {"ok": false, "reason": "loan_broke"}
	n.cash -= pay
	Wallet.earn_dirty(world, pay)
	loan["owed"] = int(loan["owed"]) - pay
	loan["paid"] = int(loan.get("paid", 0)) + pay
	return {"ok": true, "effect": "loan_collected", "amount": pay}

## A threat: they pay double from now on.
static func lean_on(world: World, me: NPCData, state: PlayerStateData, n: NPCData) -> Dictionary:
	var loan := loan_of(state, n.id)
	if loan.is_empty():
		return {"ok": false, "reason": "nothing_to_take"}
	loan["scared"] = true
	loan["fear"] = maxf(float(loan.get("fear", 0.0)), 0.9)
	n.fear = minf(1.0, n.fear + 0.5)
	MemorySystem.remember(world, state, n.id, "threatened")
	CrimeSystem.broadcast_witnesses(world, me.position, 0.15)
	return {"ok": true, "effect": "loan_leaned"}

## A beating in public: the debt's written off, every other debtor pays up.
static func make_example(world: World, me: NPCData, state: PlayerStateData, n: NPCData) -> Dictionary:
	var loan := loan_of(state, n.id)
	if loan.is_empty():
		return {"ok": false, "reason": "nothing_to_take"}
	loan["owed"] = 0
	loan["status"] = "made an example"
	n.health = maxf(0.1, n.health - 0.4)
	n.fear = 1.0
	MemorySystem.remember(world, state, n.id, "hurt")
	for other in state.loans:
		if int(other["owed"]) > 0:
			other["fear"] = maxf(float(other.get("fear", 0.0)), EXAMPLE_FEAR + reliability(other["who"]))
	state.fame = minf(100.0, state.fame + 5.0)
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.ARMED_ROBBERY])
	return {"ok": true, "effect": "loan_example"}
