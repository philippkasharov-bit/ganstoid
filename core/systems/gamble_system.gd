## BZ3: you at the table. After dark (OPEN_FROM to OPEN_TO) the back of a
## pawn shop or a liquor store runs a game (E: "Back-room game"), and so
## does any back room of your own. Two games, played in GambleWindow:
##   blackjack  bet, two cards each; hit or stand; the dealer draws to 17;
##              a natural 21 pays 3 to 2
##   dice       street craps: 7 or 11 wins, 2, 3 or 12 loses, anything else
##              is your point: roll on until the point (win) or a 7 (lose)
## Bets come out of your cash; winnings are dirty money (it's a back room).
## The window asks (ui_gamble); this system deals, every tick, with the
## sim's own in-play dice (runtime_rng). Walk away and the game ends.
class_name GambleSystem
extends SystemBase

const OPEN_FROM := 21.0
const OPEN_TO := 4.0
const TRADES := [&"pawn shop", &"liquor store"]
const BETS := [10, 50, 200]
const LEAVE_M := 8.0
const CARD := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, _tick: int) -> void:
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.gamble.is_empty():
			continue
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var at: Entity = _world.entities.get(state.gamble.get("place", &""))
		if at == null or (at.get_component(ComponentNames.BUILDING) as BuildingData).position.distance_to(me.position) > LEAVE_M:
			state.gamble = {}
			state.ui_gamble = {}
			continue
		if not state.ui_gamble.is_empty():
			play(_world, me, state, state.ui_gamble)
			state.ui_gamble = {}

## Is there a game at this building right now?
static func game_at(world: World, state: PlayerStateData, building_id: StringName) -> bool:
	var e: Entity = world.entities.get(building_id)
	var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
	if b == null:
		return false
	var h := SimClock.day_fraction(world.tick) * 24.0
	var night := h >= OPEN_FROM or h < OPEN_TO
	var mine: bool = state.venues.get(building_id, {}).get("back_room", false)
	return night and (TRADES.has(b.trade) or mine) and b.status < 2

static func sit(world: World, state: PlayerStateData, building_id: StringName) -> Dictionary:
	if not game_at(world, state, building_id):
		return {"ok": false, "reason": "closed"}
	state.gamble = {"place": building_id, "stage": "bet", "you": [], "dealer": [], "line": "Place a bet.", "bet": 0}
	return {"ok": true, "effect": "gamble_sat"}

## One request from the window.
static func play(world: World, me: NPCData, state: PlayerStateData, ask: Dictionary) -> void:
	var g := state.gamble
	var rng := world.runtime_rng
	match String(ask.get("op", "")):
		"leave":
			state.gamble = {}
		"deal":
			if g["stage"] == "play":
				return
			var bet := int(ask.get("bet", 0))
			if not BETS.has(bet) or me.cash < bet:
				g["line"] = "You don't have $%d." % bet
				return
			Wallet.spend(world, bet)
			g["bet"] = bet
			g["you"] = [_draw(rng), _draw(rng)]
			g["dealer"] = [_draw(rng), _draw(rng)]
			g["stage"] = "play"
			g["line"] = "Hit or stand?"
			if total(g["you"]) == 21:
				_settle(world, state, roundi(bet * 2.5), "Blackjack! You win $%d." % roundi(bet * 1.5))
		"hit":
			if g["stage"] != "play":
				return
			g["you"].append(_draw(rng))
			if total(g["you"]) > 21:
				_settle(world, state, 0, "Bust. You lose $%d." % int(g["bet"]))
		"stand":
			if g["stage"] != "play":
				return
			while total(g["dealer"]) < 17:
				g["dealer"].append(_draw(rng))
			var you := total(g["you"])
			var house := total(g["dealer"])
			if house > 21 or you > house:
				_settle(world, state, int(g["bet"]) * 2, "You win $%d." % int(g["bet"]))
			elif you == house:
				_settle(world, state, int(g["bet"]), "Push. Your money back.")
			else:
				_settle(world, state, 0, "House wins. You lose $%d." % int(g["bet"]))
		"dice":
			var bet := int(ask.get("bet", 0))
			if not BETS.has(bet) or me.cash < bet:
				g["line"] = "You don't have $%d." % bet
				return
			Wallet.spend(world, bet)
			g["bet"] = bet
			var rolls := [rng.randi_range(1, 6) + rng.randi_range(1, 6)]
			var first: int = rolls[0]
			var won := first in [7, 11]
			if not (won or first in [2, 3, 12]):
				while true:
					var r := rng.randi_range(1, 6) + rng.randi_range(1, 6)
					rolls.append(r)
					if r == first or r == 7:
						won = r == first
						break
			g["rolls"] = rolls
			_settle(world, state, bet * 2 if won else 0, ("You win $%d." % bet) if won else ("Crapped out. You lose $%d." % bet))

static func _settle(world: World, state: PlayerStateData, pays: int, line: String) -> void:
	if pays > 0:
		Wallet.earn_dirty(world, pays)
	state.gamble["stage"] = "done"
	state.gamble["line"] = line
	state.gamble["net"] = int(state.gamble.get("net", 0)) + pays - int(state.gamble["bet"])

static func _draw(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, 13)

## A blackjack hand's best total (aces 1 or 11).
static func total(hand: Array) -> int:
	var t := 0
	var aces := 0
	for c in hand:
		t += mini(int(c), 10) if int(c) != 1 else 11
		aces += 1 if int(c) == 1 else 0
	while t > 21 and aces > 0:
		t -= 10
		aces -= 1
	return t

static func hand_text(hand: Array) -> String:
	return " ".join(hand.map(func(c: int) -> String: return CARD[c]))
