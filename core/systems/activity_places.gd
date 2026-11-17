## NB2b: where each free-time activity can happen near someone. Shops advertise
## activities by their trade (Activities.at_trade); this finds the nearest few
## for a home, without randomness, so the same home always gets the same list.
## The business doors are bucketed by area once (like NPCOutings.prime), never
## walked on a tick. A cache only: not saved, not part of the World.
class_name ActivityPlaces
extends RefCounted

const CELL_M := 450.0      # bucket size; also the furthest a shop counts as "near"
const KEEP := 3            # places kept per activity, nearest first

var _cells := {}           # Vector2i -> [[door, trade], ...]
var _for := -1             # building count the buckets were made for
var _near := {}            # home door -> {activity: [door, ...]}

## Buckets every business door by area. Cheap to call again: only redone when
## the number of buildings changes.
func prime(world: World) -> void:
	var buildings := world.get_entities_with_component(ComponentNames.BUILDING)
	if _for == buildings.size():
		return
	_for = buildings.size()
	_cells.clear()
	_near.clear()
	for entity in buildings.values():
		var b: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and not Activities.at_trade(b.trade).is_empty():
			_cells.get_or_add(_cell(b.position), []).append([b.position, b.trade])

## activity -> up to KEEP business doors within CELL_M of `home`, nearest first.
func near(world: World, home: Vector2) -> Dictionary:
	if _near.has(home):
		return _near[home]
	prime(world)
	var found := {}
	var c := _cell(home)
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			for place in _cells.get(Vector2i(x, y), []):
				if (place[0] as Vector2).distance_to(home) <= CELL_M:
					for id in Activities.at_trade(place[1]):
						found.get_or_add(id, []).append(place[0])
	for id in found:
		var doors: Array = found[id]
		doors.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			var da := a.distance_squared_to(home)
			var db := b.distance_squared_to(home)
			return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
		found[id] = doors.slice(0, KEEP)
	_near[home] = found
	return found

## For one person: activity -> [metres from home, where]. Street and home
## activities are 0 m away; a friend's home only if they have friends; shops
## from near(). Activities with nowhere to happen are left out.
func for_person(world: World, npc: NPCData, mind: NPCMindData) -> Dictionary:
	var home := home_of(world, npc)
	var out := {}
	for id in Activities.TABLE:
		match Activities.TABLE[id]["place"]:
			"street", "home":
				out[id] = [0.0, home]
	var shops := near(world, home)
	for id in shops:
		out[id] = [home.distance_to(shops[id][0]), shops[id][0]]
	var friend := _nearest_friend(world, mind, home)
	if friend != Vector2.INF:
		out[&"visit_friend"] = [home.distance_to(friend), friend]
	return out

## Where someone's day starts and ends: their home door, a homeless person's
## camp, or where they stand.
static func home_of(world: World, npc: NPCData) -> Vector2:
	var house: Entity = world.entities.get(npc.home_building_id) if npc.home_building_id != &"" else null
	if house != null:
		return house.get_component(ComponentNames.BUILDING).position
	return npc.camp if npc.camp != Vector2.ZERO else npc.position

func _nearest_friend(world: World, mind: NPCMindData, home: Vector2) -> Vector2:
	var best := Vector2.INF
	for f in mind.friends:
		var e: Entity = world.entities.get(StringName(f))
		var friend: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if friend != null:
			var door := home_of(world, friend)
			if best == Vector2.INF or door.distance_to(home) < best.distance_to(home):
				best = door
	return best

static func _cell(p: Vector2) -> Vector2i:
	return Vector2i((p / CELL_M).floor())
