## R3D14: walking into buildings, Zomboid-style. Outside, buildings are solid
## (CityCollision) except at their front door, which lets you in when you may
## be there: your own place, a shop while it is open, or a place you broke
## into (door kicked, or the break-in you just did). Inside, the inner walls
## and furniture are solid and you go room to room through the doorways.
## A locked door says so. Containers are tied to their furniture: you reach
## one standing by it.
class_name Indoors
extends RefCounted

const REACH_M := 1.6          # how near a piece of furniture you must stand to open it
const LOCKED_EVERY_TICKS := 120

static var _said_locked := -1000000

## The player's step, through doors and round walls and furniture.
static func step(world: World, npc: NPCData, state: PlayerStateData, delta: Vector2) -> Vector2:
	var col: CityCollision = SimNav.active.collision if SimNav.active != null else null
	if col == null:
		return npc.position + delta
	var from := npc.position
	var here := col.building_at(from)
	if not here.is_empty():
		return InteriorSolid.slide(InteriorLayout.of(here), from, delta)
	var b := col.building_touching(from + delta, InteriorSolid.RADIUS + 0.1)
	if not b.is_empty() and InteriorSolid.at_door(InteriorLayout.of(b), from + delta):
		if may_enter(world, npc, state, b["id"]):
			return InteriorSolid.slide(InteriorLayout.of(b), from, delta)
		_locked(world, state)
	return _outside(col, from, delta)

## Outside: buildings solid. Touching a wall already, any step that does not
## go into a footprint is fine (so you never get stuck, and never pass a wall).
static func _outside(col: CityCollision, from: Vector2, delta: Vector2) -> Vector2:
	var stuck := col.blocked(from, InteriorSolid.RADIUS)
	for step in [delta, Vector2(delta.x, 0), Vector2(0, delta.y)]:
		var to: Vector2 = from + step
		if col.building_at(to).is_empty() and (stuck or not col.blocked(to, InteriorSolid.RADIUS)):
			return to
	return from

## May you go in? Yours, an open shop, or broken into.
static func may_enter(world: World, npc: NPCData, state: PlayerStateData, id: StringName) -> bool:
	return may_loot(world, npc, state, id) or (ShopSystem.counter_kind(world, id) != "" and ShopSystem.is_open(world, id))

## May you open its cupboards? Yours, or broken into (an open shop lets you in, not into the till).
static func may_loot(world: World, npc: NPCData, state: PlayerStateData, id: StringName) -> bool:
	var e: Entity = world.entities.get(id)
	var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
	return b != null and (Containers.is_yours(npc, b) or b.door_kicked or state.inside_id == id)

static func _locked(world: World, state: PlayerStateData) -> void:
	if world.tick - _said_locked >= LOCKED_EVERY_TICKS:
		_said_locked = world.tick
		StreetTalk.say_key(world, state, "locked")

## The building (CityData dict) you are standing in, or {}.
static func building_at(p: Vector2) -> Dictionary:
	var col: CityCollision = SimNav.active.collision if SimNav.active != null else null
	return col.building_at(p) if col != null else {}

## Inside a footprint and the place has furniture holding `kind`, but none of it in reach.
static func out_of_reach(p: Vector2, kind: String) -> bool:
	var here := building_at(p)
	if here.is_empty():
		return false   # at the door (the old way in): every container in reach
	var l := InteriorLayout.of(here)
	var held := false
	for f in l.furniture:
		if f["container"] != kind:
			continue
		held = true
		var r: Rect2 = f["rect"]
		if r.grow(REACH_M).has_point(l.to_local(p)):
			return false
	return held
