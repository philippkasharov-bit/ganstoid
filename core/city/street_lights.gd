## R3D10b: the city's street lighting, shared by the sim and the 3D view, so
## what looks dark plays dark. Lamps are the map's own plus one every
## LAMP_EVERY metres along lit streets (sides alternating, at the kerb).
## light_at() is 1 by day; at night moonlight, or more under a lamp.
## WorldDriver installs one for the district (like SimNav); with none, night
## is moonlight everywhere.
class_name StreetLights
extends RefCounted

const LAMP_R := 10.0
const LAMP_EVERY := 30.0
const LAMP_ROADS := ["art", "res", "svc"]
const MOON := 0.28
const CELL_M := 40.0

static var active: StreetLights

var lamps := PackedVector2Array()
var _grid: Dictionary = {}   # Vector2i -> PackedVector2Array

static func install(city: CityData, centre: Vector2, radius: float) -> void:
	active = build(city, centre, radius)

static func build(city: CityData, centre: Vector2, radius: float) -> StreetLights:
	var s := StreetLights.new()
	for p in CityReal.load_files().points:
		if p["kind"] == "lamp" and p["p"].distance_to(centre) < radius:
			s.lamps.append(p["p"])
	if city != null:
		s.lamps.append_array(_along_streets(city, centre, radius))
	for l in s.lamps:
		s.add(l)
	return s

func add(l: Vector2) -> void:
	var key := Vector2i((l / CELL_M).floor())
	if not _grid.has(key):
		_grid[key] = PackedVector2Array()
	_grid[key].append(l)

static func _along_streets(city: CityData, centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in city.roads:
		if not r["tier"] in LAMP_ROADS or r["pts"][0].distance_to(centre) > radius:
			continue
		var pts: PackedVector2Array = r["pts"]
		var off: float = float(r.get("w", 6.0)) * 0.5 + 0.7
		var run := LAMP_EVERY * 0.5
		var side := 1.0
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			var length := seg.length()
			while run < length and length > 0.0:
				out.append(pts[i] + seg * (run / length) + seg.normalized().orthogonal() * off * side)
				side = -side
				run += LAMP_EVERY
			run -= length
	return out

## Lamps within `reach` of `p`.
func near(p: Vector2, reach: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c := Vector2i((p / CELL_M).floor())
	var cells := ceili(reach / CELL_M)
	for x in range(c.x - cells, c.x + cells + 1):
		for y in range(c.y - cells, c.y + cells + 1):
			for l in _grid.get(Vector2i(x, y), PackedVector2Array()):
				if l.distance_to(p) < reach:
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
	return pow(maxf(0.0, 1.0 - d / r), 2.0)

## How lit `p` is at `hour`: 1 by day; at night moonlight or the lamps' pools.
static func light_at(p: Vector2, hour: float) -> float:
	var dark := darkness(hour)
	if dark <= 0.0:
		return 1.0
	var lamp := 0.0
	if active != null:
		for l in active.near(p, LAMP_R):
			lamp += pool(l.distance_to(p))
	return lerpf(1.0, maxf(MOON, minf(1.0, lamp)), dark)
