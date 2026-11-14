## R3D10b: the city's street lighting, shared by the sim and the 3D view, so
## what looks dark plays dark. Lamps are the map's own plus street lamps by
## road type (STREETS): boulevards lit on both sides with wide pools, side
## streets alternating, freeways and ramps tall and wide. Spacing runs on
## across the short pieces the map splits roads into, so no stretch is left
## dark. Each lamp is x, y and its pool radius.
## light_at() is 1 by day; at night moonlight, or more under a lamp.
## WorldDriver installs one for the district (like SimNav); with none, night
## is moonlight everywhere.
class_name StreetLights
extends RefCounted

const LAMP_R := 10.0            # the map's own lamps
## tier -> [spacing along one side, pool radius, both sides]
const STREETS := {"art": [26.0, 15.0, true], "res": [34.0, 12.0, true]}   # P1: only streets people walk; freeway and service-lot lamps landed in yards
const MIN_ROAD_M := 20.0        # a stub this short (a driveway, a lot entrance) gets no lamps
const MAX_R := 20.0              # the widest pool
const MOON := 0.28
const CELL_M := 40.0

static var active: StreetLights

var lamps := PackedVector3Array()   # x, y, pool radius
var _grid: Dictionary = {}   # Vector2i -> PackedVector3Array

static func install(city: CityData, centre: Vector2, radius: float) -> void:
	active = build(city, centre, radius)

static func build(city: CityData, centre: Vector2, radius: float) -> StreetLights:
	var s := StreetLights.new()
	var space := RoadSpace.of(city) if city != null else null   # B1: no lamp standing in the traffic
	for p in CityReal.load_files().points:
		if p["kind"] == "lamp" and p["p"].distance_to(centre) < radius:
			var at: Vector2 = space.clear(p["p"], 0.6) if space != null else p["p"]
			s.add(Vector3(at.x, at.y, LAMP_R))
	if city != null:
		var solid := CityCollision.new(city)   # P1: never a lamp inside or against a building
		for r in city.roads:
			if STREETS.has(r["tier"]) and _within(r["pts"], centre, radius) and _length(r["pts"]) >= MIN_ROAD_M:
				s._light_road(r, solid, space)
	return s

static func _length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	return total

static func _within(pts: PackedVector2Array, c: Vector2, radius: float) -> bool:
	for p in pts:
		if p.distance_to(c) < radius:
			return true
	return false

func add(l: Vector3) -> void:
	lamps.append(l)
	var key := Vector2i((Vector2(l.x, l.y) / CELL_M).floor())
	if not _grid.has(key):
		_grid[key] = PackedVector3Array()
	_grid[key].append(l)

## Lamps at the kerb every `spacing` (both sides staggered, or alternating);
## a spot too close to a lamp already there (the piece before) is skipped.
func _light_road(r: Dictionary, solid: CityCollision, space: RoadSpace) -> void:
	var spec: Array = STREETS[r["tier"]]
	var spacing: float = spec[0]
	var both: bool = spec[2]
	var off: float = float(r.get("w", 6.0)) * 0.5 + 0.7
	var pts: PackedVector2Array = r["pts"]
	var step := spacing * (0.5 if both else 1.0)
	var run := 0.0
	var side := 1.0
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var length := seg.length()
		while run <= length and length > 0.0:
			var at := space.clear(pts[i] + seg * (run / length) + seg.normalized().orthogonal() * off * side, 0.6)
			if _clear(at, step * 0.6) and not solid.blocked(at, 0.5):
				add(Vector3(at.x, at.y, spec[1]))
			side = -side
			run += step
		run -= length

func _clear(p: Vector2, gap: float) -> bool:
	for l in near(p, gap):
		return false
	return true

## Lamps within `reach` of `p` (x, y, pool radius).
func near(p: Vector2, reach: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var c := Vector2i((p / CELL_M).floor())
	var cells := ceili(reach / CELL_M)
	for x in range(c.x - cells, c.x + cells + 1):
		for y in range(c.y - cells, c.y + cells + 1):
			for l in _grid.get(Vector2i(x, y), PackedVector3Array()):
				if Vector2(l.x, l.y).distance_to(p) < reach:
					out.append(l)
	return out

## 0 by day, 1 at night, easing through dusk (18:00-20:30) and dawn (5:00-7:00).
static func darkness(hour: float) -> float:
	if hour >= 7.0 and hour <= 18.0:
		return 0.0
	if hour > 18.0:
		return smoothstep(18.0, 20.5, hour)
	return 1.0 - smoothstep(5.0, 7.0, hour)

## A lamp's pool at distance d (0..1).
static func pool(d: float, r: float = LAMP_R) -> float:
	return 1.0 - smoothstep(r * 0.3, r, d)   # full light under it, easing out to the edge

## How lit `p` is at `hour`: 1 by day; at night moonlight or the lamps' pools.
static func light_at(p: Vector2, hour: float) -> float:
	var dark := darkness(hour)
	if dark <= 0.0:
		return 1.0
	var lamp := 0.0
	if active != null:
		for l in active.near(p, MAX_R):
			lamp += pool(Vector2(l.x, l.y).distance_to(p), l.z)
	return lerpf(1.0, maxf(MOON, minf(1.0, lamp)), dark)
