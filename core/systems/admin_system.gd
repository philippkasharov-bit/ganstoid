## AD1: admin tools for testing the game in play (F11 panel, switched on in
## the pause menu). The panel only asks (PlayerStateData.ui_admin = [command,
## arg]); this system does it on the next tick, so admin changes go through
## the same loop as play and can be checked. Commands:
##   cash n · heal · god · item id · fame n · rank_up · wanted_clear
##   teleport (to your waypoint) · hour h · reveal_map · push_now · hustles_new
##   rival_max · paper_now · heist_now (rank)
## run() is also how the checks call them directly.
class_name AdminSystem
extends SystemBase

const ITEMS := [&"pistol", &"ammo", &"knife", &"bat", &"bandage", &"weed", &"burrito", &"water"]

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.ui_admin.is_empty():
			continue
		var ask := state.ui_admin
		state.ui_admin = []
		state.last_message = "ADMIN: " + run(_world, String(ask[0]), ask[1] if ask.size() > 1 else null, tick)
		state.message_alert = false
		state.message_serial += 1

## Does one command; returns what happened (for the message line and the checks).
static func run(world: World, cmd: String, arg: Variant, tick: int) -> String:
	var p: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return "no player"
	var me: NPCData = p.get_component(ComponentNames.NPC)
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	match cmd:
		"cash":
			Wallet.earn_clean(world, int(arg))
			return "+$%d" % int(arg)
		"heal":
			me.health = 1.0
			me.hunger = 1.0
			me.thirst = 1.0
			me.fatigue = 1.0
			me.bleeding = false
			me.is_down = false
			for part in state.body.keys():
				state.body[part] = BodyParts.fresh()
			return "healed, fed, rested"
		"god":
			state.admin_god = not state.admin_god
			return "god mode %s" % ("ON" if state.admin_god else "off")
		"item":
			var id := StringName(arg)
			if not ItemCatalog.ITEMS.has(id):
				return "no such item"
			state.inventory[id] = int(state.inventory.get(id, 0)) + 1
			BagGrid.sync(state)
			return "+1 %s" % String(id)
		"fame":
			Rep.add(state, float(arg))
			return "rep %s (%d)" % [Rep.name_of(state), roundi(state.fame)]
		"rank_up":
			state.rank = mini(state.rank + 1, RankSystem.NAMES.size() - 1)
			return "rank %s" % RankSystem.name_of(state.rank)
		"wanted_clear":
			state.law_tier = GanstoidEnums.LawTier.CLEAN
			state.case_evidence = 0.0
			return "police forget you"
		"teleport":
			if state.waypoint == Vector2.INF:
				return "set a waypoint on the map first (right-click)"
			me.position = state.waypoint
			me.indoors = false
			world.reindex_position(me.id)
			if SimNav.active != null:
				SimNav.active.follow(me.position)
			return "teleported"
		"hour":
			var day := int(tick / SimClock.day_ticks)
			var target := day * SimClock.day_ticks + SimClock.hours(float(arg))
			world.tick = target if target > tick else target + SimClock.day_ticks   # time only goes forward
			return "now %02d:00" % int(arg)
		"reveal_map":
			ExplorationSystem._fit(state)
			for i in state.explored.size():
				state.explored[i] = 255
			return "whole map revealed"
		"push_now":
			state.push_last = -1000000
			state.push_day = -1000000
			var cw := world.find_system(CornerWarSystem) as CornerWarSystem
			if cw == null or not state.turf_push.is_empty():
				return "a push is already on"
			var t := TerritorySystem.data(world)
			for i in 40:
				state.push_day = -1000000
				state.push_last = -1000000
				cw._maybe_push(t, state, tick + SimClock.hours(12.0 - SimClock.day_fraction(tick) * 24.0))
				if not state.turf_push.is_empty():
					return "push started"
			return "no push possible (you need two blocks next to a gang)"
		"hustles_new":
			HustleSystem.roll(world, state, state.hustle_day + 1000)
			state.hustle_day = HustleSystem.day_of(tick)
			return "three new hustles"
		"rival_max":
			RivalSystem.ensure(world, state)
			for g in state.rivals:
				state.rivals[g]["grudge"] = RivalSystem.PERSONAL
			return "every rival wants you dead"
		"heist_now":
			state.heist = {}
			var kind: String = {1: "store", 2: "stash", 3: "van"}.get(int(arg) if arg != null else 1, "store")
			var got := HeistSystem.offer(world, state, me, tick - SimClock.hours(3.0), kind)
			if got:
				state.heist["from"] = tick   # on right now
			return "score offered" if got else "no target found"
		"crib_up":
			state.crib = mini(state.crib + 1, CribSystem.TIERS.size() - 1)
			return "crib: %s" % CribSystem.TIERS[state.crib]
		"paper_now":
			state.paper = NewsSystem.print_paper(state, HustleSystem.day_of(tick))
			state.paper_serial += 1
			return "paper printed"
	return "unknown command " + cmd
