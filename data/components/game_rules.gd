## How this run plays (O1), chosen at new game, saved with it.
##   difficulty  0 Casual / 1 Normal / 2 Hardcore
##   style       0 Roleplay / 1 Street life / 2 Grind
## Every tuned number that changes with them is a multiplier read from here.
class_name GameRules
extends Resource

const DIFFICULTIES := ["Casual", "Normal", "Hardcore"]
const STYLES := ["Roleplay", "Street life", "Grind"]
const DIFFICULTY_TEXT := [
	"Go down and you wake up at home, lighter in the wallet. Police build cases slowly; bullets hurt less.",
	"Permadeath. The city as tuned.",
	"Permadeath. Cases build fast, bullets hit hard, nobody picks you up.",
]
const STYLE_TEXT := [
	"Full needs, real pace. Work shifts, pay rent on your life, live in the city.",
	"Needs at 70%, a bit more money and skill: the default.",
	"Needs barely matter, money x2, skills x3: straight to the empire.",
]

@export var difficulty: int = 1
@export var style: int = 1
@export var rescues: int = 0

func needs_rate() -> float:
	return [1.0, 0.7, 0.3][style]

func xp_mult() -> float:
	return [1.0, 1.5, 3.0][style]

func money_mult() -> float:
	return [1.0, 1.2, 2.0][style]

func evidence_mult() -> float:
	return [0.6, 1.0, 1.4][difficulty]

func damage_to_player() -> float:
	return [0.6, 1.0, 1.5][difficulty]

func rescue() -> bool:
	return difficulty == 0

const ENTITY := &"rules"

static func of(world: World) -> GameRules:
	var e: Entity = world.entities.get(ENTITY) if world != null else null
	return e.get_component(&"GameRules") if e != null else null

static func install(world: World, difficulty_i: int, style_i: int) -> GameRules:
	var r := of(world)
	if r == null:
		r = GameRules.new()
		var e := Entity.new(ENTITY)
		e.add_component(r)
		world.register_entity(e)
	r.difficulty = difficulty_i
	r.style = style_i
	return r

## Multipliers with defaults when no rules exist (checks, old saves).
static func needs(world: World) -> float:
	var r := of(world)
	return r.needs_rate() if r != null else 1.0

static func xp(world: World) -> float:
	var r := of(world)
	return r.xp_mult() if r != null else 1.0

static func money(world: World) -> float:
	var r := of(world)
	return r.money_mult() if r != null else 1.0

static func evidence(world: World) -> float:
	var r := of(world)
	return r.evidence_mult() if r != null else 1.0

static func hurt(world: World) -> float:
	var r := of(world)
	return r.damage_to_player() if r != null else 1.0
