## MP2: fog of war for the map. The city is a grid of CELL_M squares; the ones
## within REVEAL_M of you are explored for good (a bitset on PlayerStateData,
## saved). Street dealers and fixers you have actually seen are remembered by
## id, so the map can show them. Checked twice a second.
class_name ExplorationSystem
extends SystemBase

const CELL_M := 25.0
const GRID := 300                 # 300 x 25 m = 7.5 km: the whole map
const REVEAL_M := 45.0
const KNOW_M := 20.0              # a dealer or fixer this close, in sight, is known
const EVERY := 30
const HOME_KNOWN_M := 220.0       # a new life (or a save from before MP2) knows its own neighbourhood

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != 0:
		return
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		if me.is_down:
			continue
		if state.explored.size() != GRID * GRID / 8:
			reveal(state, me.position, HOME_KNOWN_M)
		reveal(state, me.position, REVEAL_M)
		for id in _world.spatial_index.query_nearby(me.position):
			if state.known.has(id):
				continue
			var e: Entity = _world.entities.get(id)
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n != null and (n.is_dealer or n.is_fixer) and not n.is_down and n.position.distance_to(me.position) <= KNOW_M and CrimeSystem.can_see(_world, me.position, n.position):
				state.known[id] = "dealer" if n.is_dealer else "fixer"

## Marks every cell within `r` of `at` explored.
static func reveal(state: PlayerStateData, at: Vector2, r: float) -> void:
	_fit(state)
	var lo := ((at - Vector2(r, r)) / CELL_M).floor()
	var hi := ((at + Vector2(r, r)) / CELL_M).floor()
	for x in range(maxi(0, int(lo.x)), mini(GRID - 1, int(hi.x)) + 1):
		for y in range(maxi(0, int(lo.y)), mini(GRID - 1, int(hi.y)) + 1):
			if ((Vector2(x, y) + Vector2(0.5, 0.5)) * CELL_M).distance_to(at) <= r + CELL_M * 0.5:
				var i := y * GRID + x
				state.explored[i >> 3] |= 1 << (i & 7)

static func explored(state: PlayerStateData, p: Vector2) -> bool:
	var c := (p / CELL_M).floor()
	if c.x < 0 or c.y < 0 or c.x >= GRID or c.y >= GRID or state.explored.size() != GRID * GRID / 8:
		return false
	var i := int(c.y) * GRID + int(c.x)
	return state.explored[i >> 3] & (1 << (i & 7)) != 0

## How many cells are explored (checks).
static func count(state: PlayerStateData) -> int:
	var n := 0
	for b in state.explored:
		while b:
			n += b & 1
			b >>= 1
	return n

## A save from before MP2, or a damaged one: start from an empty fog.
static func _fit(state: PlayerStateData) -> void:
	if state.explored.size() != GRID * GRID / 8:
		state.explored = PackedByteArray()
		state.explored.resize(GRID * GRID / 8)
