## NB2a: what people do with their free time, as data. A new activity is a new
## entry here, not new code. Nothing reads this in play until NB2c.
##
## Each activity:
##   label     what the People tab and reports call it
##   place     where it happens: "shop" (a business whose trade is in `trades`),
##             "street" (a walk with no destination), "home" (their own door),
##             "friend" (a friend's home door)
##   walk      how the walker carries it out: "visit" (go in for `stay`),
##             "stroll" (a few turns round the block), "linger" (stand outside
##             for `stay`), "none" (no trip at all)
##   hours     [from, to] game hours it is done in; to < from wraps past midnight
##   stay      [min, max] game minutes spent there
##   fills     MindDrive -> how much one go satisfies it (0..1)
##   likes     MindTrait -> how much that trait makes it appealing (-1..1)
##   cost      typical dollars spent
class_name Activities
extends RefCounted

const D := GanstoidEnums.MindDrive
const T := GanstoidEnums.MindTrait

const PLACES := ["shop", "street", "home", "friend"]
const WALKS := ["visit", "stroll", "linger", "none"]

## Shop trades nobody visits on their free time (only guests and staff go in).
const PRIVATE_TRADES := [&"motel"]

const TABLE := {
	&"shop": {
		"label": "Go shopping", "place": "shop", "walk": "visit", "hours": [8.0, 21.0], "stay": [8.0, 30.0],
		"trades": [&"corner store", &"liquor store", &"sneaker store", &"record store", &"swap meet stall", &"pawn shop", &"gas station"],
		"fills": {D.FUN: 0.2, D.SOCIAL: 0.1}, "likes": {T.GREEDY: 0.3, T.CURIOUS: 0.3, T.PATIENT: -0.2}, "cost": 15,
	},
	&"eat": {
		"label": "Eat out", "place": "shop", "walk": "visit", "hours": [7.0, 23.0], "stay": [15.0, 45.0],
		"trades": [&"diner", &"taco stand"],
		"fills": {D.FOOD: 0.8, D.SOCIAL: 0.2}, "likes": {T.SOCIABLE: 0.3, T.GREEDY: -0.2}, "cost": 8,
	},
	&"coffee": {
		"label": "Grab a coffee", "place": "shop", "walk": "visit", "hours": [6.0, 12.0], "stay": [5.0, 20.0],
		"trades": [&"diner", &"corner store", &"gas station"],
		"fills": {D.ENERGY: 0.25, D.FOOD: 0.1}, "likes": {T.ENERGETIC: 0.3, T.PATIENT: -0.1}, "cost": 2,
	},
	&"errands": {
		"label": "Run errands", "place": "shop", "walk": "visit", "hours": [9.0, 17.0], "stay": [10.0, 40.0],
		"trades": [&"check cashing", &"bank branch", &"laundromat", &"clinic", &"office"],
		"fills": {D.SAFETY: 0.2}, "likes": {T.LAWFUL: 0.4, T.PATIENT: 0.3, T.ENERGETIC: -0.1}, "cost": 10,
	},
	&"groom": {
		"label": "Get a haircut", "place": "shop", "walk": "visit", "hours": [9.0, 19.0], "stay": [25.0, 60.0],
		"trades": [&"barbershop", &"beauty salon"],
		"fills": {D.SOCIAL: 0.4, D.FUN: 0.2}, "likes": {T.SOCIABLE: 0.4, T.PATIENT: 0.2}, "cost": 12,
	},
	&"night_out": {
		"label": "Night out", "place": "shop", "walk": "visit", "hours": [18.0, 2.0], "stay": [40.0, 120.0],
		"trades": [&"diner", &"taco stand", &"liquor store", &"record store"],
		"fills": {D.FUN: 0.6, D.SOCIAL: 0.5}, "likes": {T.SOCIABLE: 0.5, T.ENERGETIC: 0.4, T.PATIENT: -0.2, T.PARANOID: -0.3}, "cost": 20,
	},
	&"stroll": {
		"label": "Take a walk", "place": "street", "walk": "stroll", "hours": [6.0, 24.0], "stay": [0.0, 0.0],
		"trades": [],
		"fills": {D.FUN: 0.3, D.ENERGY: -0.1}, "likes": {T.ENERGETIC: 0.4, T.CURIOUS: 0.4, T.PARANOID: -0.3}, "cost": 0,
	},
	&"hang_out": {
		"label": "Hang out on the stoop", "place": "home", "walk": "linger", "hours": [10.0, 23.0], "stay": [20.0, 90.0],
		"trades": [],
		"fills": {D.SOCIAL: 0.3, D.FUN: 0.3}, "likes": {T.SOCIABLE: 0.4, T.PATIENT: 0.3, T.LAWFUL: -0.2, T.ENERGETIC: -0.2}, "cost": 0,
	},
	&"visit_friend": {
		"label": "Visit a friend", "place": "friend", "walk": "visit", "hours": [10.0, 22.0], "stay": [30.0, 120.0],
		"trades": [],
		"fills": {D.SOCIAL: 0.7, D.FUN: 0.3}, "likes": {T.SOCIABLE: 0.6, T.PARANOID: -0.2}, "cost": 0,
	},
	&"stay_in": {
		"label": "Stay in", "place": "home", "walk": "none", "hours": [0.0, 24.0], "stay": [60.0, 180.0],
		"trades": [],
		"fills": {D.ENERGY: 0.4, D.SAFETY: 0.3}, "likes": {T.PARANOID: 0.4, T.ENERGETIC: -0.4, T.SOCIABLE: -0.3}, "cost": 0,
	},
}

static var _by_trade := {}   # trade -> [activity ids], built on first use

## The activities a business of this trade offers (a diner: eat, coffee, night out).
static func at_trade(trade: StringName) -> Array:
	if _by_trade.is_empty():
		for id in TABLE:
			for t in TABLE[id]["trades"]:
				_by_trade.get_or_add(t, []).append(id)
	return _by_trade.get(trade, [])

## Whether `id` is done at this hour (0..24), with spans that wrap past midnight.
static func is_open(id: StringName, hour: float) -> bool:
	var span: Array = TABLE[id]["hours"]
	if span[1] >= span[0]:
		return hour >= span[0] and hour < span[1]
	return hour >= span[0] or hour < span[1]
