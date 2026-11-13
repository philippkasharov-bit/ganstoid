## R3D15: who is in the building you are in. People the sim has indoors
## stand at their home's or workplace's door point; when you are in that
## building they are drawn in its rooms instead: on their feet somewhere in
## a room, clear of the furniture, or lying in a bed at night. Where each
## one stands is seeded by who they are and the hour, so it holds still
## while you look and moves on when the hour turns.
class_name IndoorPeople3D
extends RefCounted

const DOOR_M := 3.0          # an indoor person this near the door is in this building
const NIGHT_FROM := 23.0
const NIGHT_TO := 7.0

## id -> [map point, facing, lying] for everyone indoors in building `b`.
static func place(world: World, b: Dictionary) -> Dictionary:
	var out := {}
	var l := InteriorLayout.of(b)
	var hour := SimClock.day_fraction(world.tick) * 24.0
	var night := hour >= NIGHT_FROM or hour < NIGHT_TO
	var beds := l.furniture.filter(func(f: Dictionary) -> bool: return f["name"] == "bed")
	var people := world.get_entities_with_component(ComponentNames.NPC)
	for id in people:
		var npc: NPCData = people[id].get_component(ComponentNames.NPC)
		if not npc.indoors or npc.position.distance_to(b["door"]) > DOOR_M or not _belongs(npc, b["id"]):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([id, int(hour)])
		if night and npc.home_building_id == b["id"] and not beds.is_empty():
			var bed: Rect2 = beds[out.size() % beds.size()]["rect"]
			out[id] = [l.to_map(bed.get_center()), l.angle + PI * 0.5, true]
		else:
			out[id] = [_free_spot(l, rng), rng.randf() * TAU, false]
	return out

static func _belongs(npc: NPCData, building_id: StringName) -> bool:
	return npc.home_building_id == building_id or npc.work_building_id == building_id

## A point in some room, clear of walls and furniture (the room's middle if nothing clear turns up).
static func _free_spot(l: InteriorLayout, rng: RandomNumberGenerator) -> Vector2:
	var room: Rect2 = l.rooms[rng.randi() % l.rooms.size()]
	for attempt in 12:
		var p := l.to_map(room.position + Vector2(rng.randf(), rng.randf()) * room.size)
		if Geometry2D.is_point_in_polygon(p, l.poly) and InteriorSolid.clearance(l, p) > 0.45:
			return p
	return l.to_map(room.get_center())
