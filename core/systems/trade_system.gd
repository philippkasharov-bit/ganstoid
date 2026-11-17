## UI7: the deal window and the pawn / fence window, run here (the window
## only asks, through ui_trade). Deal: offer one of what you carry to the
## person in front of you at your price (StreetDeal), adjust the price
## between offers. Pawn / fence: sell your valuables one by one or all
## (Fence). Walk away and the window closes.
class_name TradeSystem
extends SystemBase

const LEAVE_M := 5.0

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

## Opens the window: mode "deal" (who = a person), "pawn" or "fence" (who = the counter).
static func open(state: PlayerStateData, mode: String, who: StringName) -> Dictionary:
	state.trade = {"mode": mode, "who": who, "line": "", "tone": 0}
	return {}

func process_entities(entities: Dictionary, _delta: float, _tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.trade.is_empty():
			continue
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var at := where(_world, state.trade.get("who", &""))
		if at == Vector2.INF or at.distance_to(me.position) > LEAVE_M or me.is_down:
			state.trade = {}
			state.ui_trade = {}
			continue
		if not state.ui_trade.is_empty():
			act(_world, me, state, state.ui_trade)
			state.ui_trade = {}

## What each kind of buyer pays for loot.
static func share_of(mode: String) -> float:
	return {"pawn": Fence.PAWN_SHARE, "ring": Rackets.RING_SHARE}.get(mode, Fence.FENCE_SHARE)

static func where(world: World, id: StringName) -> Vector2:
	var e: Entity = world.entities.get(id)
	if e == null:
		return Vector2.INF
	var n: NPCData = e.get_component(ComponentNames.NPC)
	if n != null:
		return n.position
	var b: BuildingData = e.get_component(ComponentNames.BUILDING)
	return b.position if b != null else Vector2.INF

static func act(world: World, me: NPCData, state: PlayerStateData, ask: Dictionary) -> void:
	var t := state.trade
	var r := {}
	match String(ask.get("op", "")):
		"close":
			state.trade = {}
			return
		"price":
			DrugLabSystem.set_price(state, ask["good"], int(ask.get("set", 0)))
			return
		"offer":
			var e: Entity = world.entities.get(t["who"])
			var buyer: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if buyer != null:
				r = StreetDeal.sell(world, me, state, buyer, ask["good"])
		"sell":
			r = Fence.sell_one(world, state, ask["id"], share_of(t["mode"]), t["mode"] == "pawn")
		"sell_all":
			r = Fence._sell(world, state, share_of(t["mode"]), t["mode"] == "pawn")
	if r.is_empty():
		return
	StreetTalk.say(world, state, r)
	t["line"] = state.last_message
	t["tone"] = 1 if r.get("ok", false) else -1
