## VS2A: the kerb as continuous runs, worked out as data (StreetDetail3D draws
## them, verify_kerbs checks them). Each edge of a kerbed road is one line
## offset from the centre line by half the road width, mitred at every bend
## (and across the joint to the road that continues it), so bends have no gap
## and no overlap. Along that line:
##   a street crossing (another real street, not parallel) cuts the kerb, and
##     each cut end turns the corner in a rounded return: half of a fillet arc,
##     radius RADIUS by tier; the other street's kerb draws the other half
##   a driveway, or a lot road (service road, alley, aisle) coming in, drops
##     the kerb to KERB_LOW with a sloped flare either side
##   a crosswalk ramp (city.kerb_ramps) drops it flush with the road
## Cuts are found by sampling the line every SAMPLE_M and bisected to a
## centimetre, so ends sit exactly where the crossing road's edge is.
## A run: {road, side, tier, pts, out (unit, towards the sidewalk), h, zone
## (per point: 1 in a drop or its flare), red (per piece: by a hydrant),
## ends: [reason, reason], partner: [bool, bool] (another run's end meets it), ramps: [[c, along, w, len, out]], meters: [[p, along, out]]}.
## End reasons: "junction" (a rounded return), "corner" (a cut with no room
## for a return), "continuation" (another road's run carries on), "road_end".
class_name KerbRuns
extends RefCounted

const KERBED := ["art", "res"]
const STREET := ["art", "res", "ramp", "hill", "fwy"]   # crossing these ends the kerb at a corner
const LOTS := ["svc", "alley", "drive", "aisle"]         # crossing these drops the kerb, like a driveway
const RADIUS := {"art": 8.0, "res": 5.0}                 # a corner's return (the larger of the two streets)
const SAMPLE_M := 0.5
const JOIN_M := 0.6            # road ends this close carry each other on
const CARRY_M := 12.0          # ... and do not cut each other's kerb this near their joint
const CARRY_COS := 0.86        # only a gentle join (under about 30 degrees) carries on; a sharper one is a corner
const FLARE_M := 0.6           # a dropped kerb slopes back up over this
const RAMP_FLARE_M := 0.45
const NEAR_M := 1.2            # a driveway or ramp this near the kerb line belongs to it
const MAX_RETURN_M := 9.0      # a return never reaches further back than this
const ARC_STEP := deg_to_rad(10.0)
const MITRE_MAX := 2.5
const CELL_M := 24.0
const RED_M := 4.5             # no parking (red kerb) this near a hydrant
const HYDRANT_M := 5.5         # a hydrant this far behind the kerb (across the sidewalk) still reds it
const METER_M := 6.0           # a metered space on an arterial

var city: CityData
var _cross := {}     # cell -> [[a, b, half, road, street?]]
var _drives := {}    # cell -> [c, dir, w]
var _ramps := {}     # cell -> [c, dir, w, len]
var _hydrants := {}  # cell -> Vector2
var _ends := {}      # 0.5 m cell -> [[road, end (0|1)]]
var _carry := {}     # road -> {road that carries it on: the joint} (never cuts its kerb near the joint)

## Runs for every kerbed road with a segment within `reach` of `centre`;
## `keep` (if set) drops runs whose first point it says no to (another chunk's).
static func build(city_data: CityData, real: CityReal, centre: Vector2, reach: float, keep: Callable = Callable()) -> Array[Dictionary]:
	var k := KerbRuns.new()
	k.city = city_data
	k._index(real, centre, reach + 220.0)   # a kerbed road can reach well past `reach`: index what its far end may cross
	var out: Array[Dictionary] = []
	for i in city_data.roads.size():
		var r: Dictionary = city_data.roads[i]
		if r["tier"] in KERBED and _seg_near(r["pts"], centre, reach):
			for side in [-1.0, 1.0]:
				for run in k._road_side(i, side):
					if not keep.is_valid() or keep.call(run["pts"][0]):
						out.append(run)
	return out

static func _seg_near(pts: PackedVector2Array, c: Vector2, reach: float) -> bool:
	for i in pts.size() - 1:
		if Geometry2D.get_closest_point_to_segment(c, pts[i], pts[i + 1]).distance_to(c) < reach:
			return true
	return pts.size() == 1 and pts[0].distance_to(c) < reach

static func half_of(r: Dictionary) -> float:
	return float(r.get("w", CityMesh3D.ROAD_W.get(r["tier"], 6.0))) * 0.5

static func _cell(p: Vector2) -> Vector2i:
	return Vector2i((p / CELL_M).floor())

func _index(real: CityReal, centre: Vector2, reach: float) -> void:
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		var street: bool = r["tier"] in STREET
		if not (street or r["tier"] in LOTS) or not _seg_near(r["pts"], centre, reach):
			continue
		var half := half_of(r)
		var pts: PackedVector2Array = r["pts"]
		for s in pts.size() - 1:
			_file(_cross, pts[s], pts[s + 1], half + 2.0, [pts[s], pts[s + 1], half, i, street])
		if r["tier"] in KERBED:
			for e in 2:
				var p: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
				_ends.get_or_add(Vector2i((p * 2.0).round()), []).append([i, e])
	for d in city.driveways:
		if d["c"].distance_to(centre) < reach:
			_file(_drives, d["c"], d["c"], 2.0, [d["c"], d["dir"], float(d["w"])])
	for d in city.kerb_ramps:
		if d["c"].distance_to(centre) < reach:
			_file(_ramps, d["c"], d["c"], 2.0, [d["c"], d["dir"], float(d["w"]), float(d["len"])])
	for p in real.points:
		if p["kind"] == "hydrant" and p["p"].distance_to(centre) < reach:
			_file(_hydrants, p["p"], p["p"], RED_M, p["p"])

func _file(grid: Dictionary, a: Vector2, b: Vector2, grow: float, item: Variant) -> void:
	var lo := _cell(a.min(b) - Vector2.ONE * grow)
	var hi := _cell(a.max(b) + Vector2.ONE * grow)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			grid.get_or_add(Vector2i(x, y), []).append(item)

## The road that carries road `own` on at its end `p` (the most nearly straight on,
## and only if `own` is that road's best way on too), as [its direction away from
## the joint, its half width, its index], or [] if none.
func _carried(own: int, p: Vector2, away: Vector2) -> Array:
	var best := _best_on(own, p, away)
	if best.is_empty():
		return []
	var r: Dictionary = city.roads[best[2]]
	var back := _best_on(best[2], p, best[0])   # does it pick us back?
	if back.is_empty() or int(back[2]) != own:
		return []
	_carry.get_or_add(own, {})[best[2]] = p
	return best

func _best_on(own: int, p: Vector2, away: Vector2) -> Array:
	var best: Array = []
	var best_dot := CARRY_COS
	var key := Vector2i((p * 2.0).round())
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for e in _ends.get(key + Vector2i(dx, dy), []):
				if e[0] == own:
					continue
				var r: Dictionary = city.roads[e[0]]
				var pts: PackedVector2Array = r["pts"]
				var q: Vector2 = pts[0] if e[1] == 0 else pts[pts.size() - 1]
				var nxt: Vector2 = pts[1] if e[1] == 0 else pts[pts.size() - 2]
				if q.distance_to(p) > JOIN_M or nxt.distance_to(q) < 0.05:
					continue
				var v := (nxt - q).normalized()
				var d := -v.dot(away)   # straight on: their way out is opposite ours
				if d > best_dot:
					best_dot = d
					best = [v, half_of(r), e[0]]
	return best

## The kerb line of one side of road `i`: offset points, outward normals (mitred).
func _line(i: int, side: float) -> Array:
	var r: Dictionary = city.roads[i]
	var raw: PackedVector2Array = r["pts"]
	var pts := PackedVector2Array([raw[0]])
	for p in raw:
		if p.distance_to(pts[pts.size() - 1]) > 0.2:
			pts.append(p)
	if pts.size() < 2:
		return []
	var half := half_of(r)
	var n: Array[Vector2] = []
	for k in pts.size() - 1:
		n.append((pts[k + 1] - pts[k]).normalized().orthogonal() * side)
	var line := PackedVector2Array()
	var outs := PackedVector2Array()
	var ends := ["road_end", "road_end"]
	for k in pts.size():
		var before: Vector2 = n[k - 1] if k > 0 else Vector2.ZERO
		var after: Vector2 = n[k] if k < n.size() else Vector2.ZERO
		var h := half
		if k == 0 or k == pts.size() - 1:   # carried on by another road? mitre across the joint
			var away := (pts[1] - pts[0]).normalized() if k == 0 else (pts[k - 1] - pts[k]).normalized()
			var c := _carried(i, pts[k], away)
			if not c.is_empty():
				var travel: Vector2 = -c[0] if k == 0 else c[0]   # their direction along our way of travel
				var theirs: Vector2 = travel.orthogonal() * side
				if k == 0:
					before = theirs
				else:
					after = theirs
				h = maxf(half, float(c[1]))   # both meet at the wider road's edge; the narrower one fans out to it
				ends[0 if k == 0 else 1] = "continuation"
		var m := (before + after).normalized()
		var lean := m.dot(after if after != Vector2.ZERO else before)
		line.append(pts[k] + m * h / maxf(lean, 1.0 / MITRE_MAX))
		outs.append(m)
	return [line, outs, ends]

## Distance along a polyline to each point.
static func _lengths(pts: PackedVector2Array) -> PackedFloat32Array:
	var s := PackedFloat32Array([0.0])
	for k in pts.size() - 1:
		s.append(s[k] + pts[k].distance_to(pts[k + 1]))
	return s

## The point at distance `t` along `pts` (with `s` its lengths), and the segment it lies on.
static func _at(pts: PackedVector2Array, s: PackedFloat32Array, t: float) -> Array:
	t = clampf(t, 0.0, s[s.size() - 1])
	var k := 0
	while k < s.size() - 2 and s[k + 1] < t:
		k += 1
	var seg := maxf(s[k + 1] - s[k], 0.0001)
	return [pts[k].lerp(pts[k + 1], (t - s[k]) / seg), k]

## The street (or lot road) whose carriageway covers `p`, other than `own` and the
## roads that carry `own` on (their joint is not a crossing): [road, item] or [].
func _hit(p: Vector2, own: int, street: bool) -> Array:
	var carry: Dictionary = _carry.get(own, {})
	for it in _cross.get(_cell(p), []):
		if it[3] == own or bool(it[4]) != street:
			continue
		if carry.has(it[3]) and (carry[it[3]] as Vector2).distance_to(p) < CARRY_M:
			continue
		if Geometry2D.get_closest_point_to_segment(p, it[0], it[1]).distance_to(p) < float(it[2]):
			return [it[3], it]
	return []

## Is `p` inside a street other than `a` and `b`?
func _in_third(p: Vector2, a: int, b: int) -> bool:
	for it in _cross.get(_cell(p), []):
		if not bool(it[4]) or it[3] == a or it[3] == b:
			continue
		if Geometry2D.get_closest_point_to_segment(p, it[0], it[1]).distance_to(p) < float(it[2]):
			return true
	return false

## Runs (kept stretches) of one side of road `i`.
func _road_side(i: int, side: float) -> Array[Dictionary]:
	var got := _line(i, side)
	var runs: Array[Dictionary] = []
	if got.is_empty():
		return runs
	var line: PackedVector2Array = got[0]
	var outs: PackedVector2Array = got[1]
	var s := _lengths(line)
	var total := s[s.size() - 1]
	# 1. where street mouths cut it, and where lot roads come in
	var steps := maxi(1, ceili(total / SAMPLE_M))
	var cuts: Array = []      # [s0, s1, item at s0, item at s1]
	var lots: Array = []      # [s0, s1]
	var open_cut := -1.0
	var open_item: Array = []
	var open_lot := -1.0
	var last_item: Array = []
	for j in steps + 1:
		var t := total * j / steps
		var a := _at(line, s, t)
		var hit := _hit(a[0], i, true)
		if not hit.is_empty() and open_cut < 0.0:
			open_cut = _edge(line, s, total * (j - 1) / steps, t, i, true) if j > 0 else 0.0
			open_item = hit[1]
		elif hit.is_empty() and open_cut >= 0.0:
			cuts.append([open_cut, _edge(line, s, t, total * (j - 1) / steps, i, true), open_item, last_item])
			open_cut = -1.0
		if not hit.is_empty():
			last_item = hit[1]
		var lot := _hit(a[0], i, false)
		if not lot.is_empty() and open_lot < 0.0:
			open_lot = t
		elif lot.is_empty() and open_lot >= 0.0:
			lots.append([open_lot, t])
			open_lot = -1.0
	if open_cut >= 0.0:
		cuts.append([open_cut, total + 1.0, open_item, last_item])
	if open_lot >= 0.0:
		lots.append([open_lot, total])
	# 2. the kept stretches between cuts, each end a return, a carry-on or a road end
	var keep: Array = []
	var from := 0.0
	var from_why: String = got[2][0]
	var from_item: Array = []
	for c in cuts:
		if c[0] > from:
			keep.append([from, c[0], from_why, "junction", from_item, c[2]])
		from = c[1]
		from_why = "junction"
		from_item = c[3]
	if from < total:
		keep.append([from, total, from_why, got[2][1], from_item, []])
	for k in keep:
		var run := _stretch(i, side, line, outs, s, k, lots)
		if not run.is_empty() and not _buried(run):
			runs.append(run)
	return runs

## A stretch lying mostly inside another street (two roads mapped overlapping, as
## where a road splits): a kerb there would sit in the asphalt, so it is left out.
func _buried(run: Dictionary) -> bool:
	var pts: PackedVector2Array = run["pts"]
	var inside := 0
	for p in pts:
		if _in_third(p, int(run["road"]), -1):
			inside += 1
	return inside * 2 > pts.size()

## Bisects between a sample off a carriageway (`clear_t`) and one on it (`hit_t`): the edge, to a centimetre.
func _edge(line: PackedVector2Array, s: PackedFloat32Array, clear_t: float, hit_t: float, own: int, street: bool) -> float:
	for n in 8:
		var mid := (clear_t + hit_t) * 0.5
		if _hit(_at(line, s, mid)[0], own, street).is_empty():
			clear_t = mid
		else:
			hit_t = mid
	return clear_t

## One kept stretch [t0, t1] as a run: trimmed for its returns, arcs added, drops and red marked.
func _stretch(i: int, side: float, line: PackedVector2Array, outs: PackedVector2Array, s: PackedFloat32Array, k: Array, lots: Array) -> Dictionary:
	var tier: String = city.roads[i]["tier"]
	var t0: float = k[0]
	var t1: float = k[1]
	var why := [k[2], k[3]]
	var arcs := [PackedVector2Array(), PackedVector2Array()]
	var partner := [why[0] == "continuation", why[1] == "continuation"]   # another run's end should meet this one
	var with := [-1, -1]   # the street each return turns onto
	var centres := [Vector2.ZERO, Vector2.ZERO]
	for e in 2:
		if why[e] != "junction":
			continue
		var t: float = t0 if e == 0 else t1
		var a := _at(line, s, t)
		var seg: int = a[1]
		var fwd := (line[seg + 1] - line[seg]).normalized()
		var d: Vector2 = -fwd if e == 0 else fwd   # towards the corner
		var out: Vector2 = fwd.orthogonal() * side
		var ret := _return(a[0], d, out, k[4 + e], tier, i)
		if ret.is_empty() or float(ret[0]) > (t1 - t0) - 0.3:
			why[e] = "corner"
			continue
		if e == 0:
			t0 += ret[0]
		else:
			t1 -= ret[0]
		arcs[e] = ret[1]
		centres[e] = ret[2]
		partner[e] = ret[3]
		with[e] = int((k[4 + e] as Array)[3])
	if t1 - t0 < 0.3:
		return {}
	# the polyline: start arc (reversed), the kept line, end arc
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var arc_len := [0.0, 0.0]
	var a0 := arcs[0] as PackedVector2Array
	for j in range(a0.size() - 1, -1, -1):
		pts.append(a0[j])
		nrm.append((centres[0] - a0[j]).normalized())
	var p0 := _at(line, s, t0)
	pts.append(p0[0])
	nrm.append((line[p0[1] + 1] - line[p0[1]]).normalized().orthogonal() * side)
	for j in s.size():
		if s[j] > t0 + 0.01 and s[j] < t1 - 0.01:
			pts.append(line[j])
			nrm.append(outs[j])
	var p1 := _at(line, s, t1)
	pts.append(p1[0])
	nrm.append((line[p1[1] + 1] - line[p1[1]]).normalized().orthogonal() * side)
	var a1 := arcs[1] as PackedVector2Array
	for j in a1.size():
		pts.append(a1[j])
		nrm.append((centres[1] - a1[j]).normalized())
	var run := {"road": i, "side": side, "tier": tier, "pts": pts, "out": nrm, "ends": why, "partner": partner, "with": with, "ramps": [], "meters": []}
	_drops(run, line, s, t0, a0.size(), lots)
	return run

## The rounded return where a kerb at `e` heading `d` (towards the corner, the
## sidewalk on its `out` side) meets the crossing street `item`'s kerb:
## [how far the run is trimmed back, the half arc from the trimmed end to the
## arc's middle (the whole arc where the other street has no kerb), the arc
## centre, whether the other street's kerb draws the other half], or [].
func _return(e: Vector2, d: Vector2, out: Vector2, item: Array, tier: String, own: int) -> Array:
	if item.is_empty():
		return []
	var road: Dictionary = city.roads[item[3]]
	var mine: Dictionary = city.roads[own]
	# Both streets' kerb lines from the centre-line pieces nearest the corner, found
	# twice (first near the kerb end, then near the corner found), so the two
	# streets work out the very same corner and their half arcs meet.
	var corner: Variant = e
	var tj := Vector2.ZERO
	var edge_p := Vector2.ZERO
	var line_p := e
	for pass_n in 2:
		var near: Vector2 = corner
		var theirs := _piece_near(road["pts"], near)
		var ours := _piece_near(mine["pts"], near)
		if theirs.is_empty() or ours.is_empty():
			return []
		tj = (theirs[1] - theirs[0]).normalized()
		var nj := tj.orthogonal()
		if (e - theirs[0]).dot(nj) < 0.0:
			nj = -nj
		edge_p = theirs[0] + nj * half_of(road)
		var ti: Vector2 = (ours[1] - ours[0]).normalized()
		d = ti if ti.dot(d) > 0.0 else -ti
		out = ti.orthogonal()
		if out.dot((e - ours[0])) < 0.0:
			out = -out
		line_p = ours[0] + out * half_of(mine)
		corner = Geometry2D.line_intersects_line(line_p, d, edge_p, tj)
		if corner == null or (corner as Vector2).distance_to(e) > 6.0:
			return []
	var other: String = road["tier"]
	var whole: bool = not other in KERBED   # no kerb on the other side to draw its half: draw the whole return
	var u := tj if tj.dot(out) > 0.0 else -tj   # their kerb leaves the corner on our sidewalk side
	var phi := absf(d.angle_to(u))
	if phi < deg_to_rad(15.0) or phi > deg_to_rad(165.0):
		return []
	var full := maxf(RADIUS.get(tier, 5.0), RADIUS.get(other, 5.0))
	for shrink in [1.0, 0.5, 0.25]:   # a return that would swing into a third street gets tighter
		var radius: float = full * shrink
		var reach := radius * tan(phi * 0.5)
		if reach > MAX_RETURN_M:
			radius *= MAX_RETURN_M / reach
			reach = MAX_RETURN_M
		var start: Vector2 = corner as Vector2 - d * reach
		var centre := start + out * radius
		var sweep := phi if whole else phi * 0.5
		var steps := maxi(1, ceili(sweep / ARC_STEP))
		var turn := signf(d.cross(out))   # which way round the centre the kerb turns
		var arc := PackedVector2Array()
		var clear := true
		for j in range(1, steps + 1):
			var q := centre + (start - centre).rotated(turn * sweep * j / steps)
			arc.append(q)
			if _in_third(q, own, item[3]):
				clear = false
		if clear:
			var back := reach - (corner as Vector2 - e).dot(d)   # trimmed back from e by this (negative: carried on)
			return [back, arc, centre, not whole and shrink == 1.0]
	return []

## The piece of the polyline `pts` nearest `p`: [a, b], or [] if it has none.
static func _piece_near(pts: PackedVector2Array, p: Vector2) -> Array:
	var best: Array = []
	var near := INF
	for k in pts.size() - 1:
		if pts[k].distance_to(pts[k + 1]) < 0.05:
			continue
		var dk := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1]).distance_to(p)
		if dk < near:
			near = dk
			best = [pts[k], pts[k + 1]]
	return best

## Driveways, lot entrances and ramps along the run: heights and zone marks; hydrants: red pieces; meters.
func _drops(run: Dictionary, line: PackedVector2Array, s: PackedFloat32Array, t0: float, lead: int, lots: Array) -> void:
	var pts: PackedVector2Array = run["pts"]
	var ls := _lengths(pts)
	var lead_len: float = ls[lead]   # where the kept line starts (after the start arc)
	var zones: Array = []   # [from, to, low, flare]
	for lot in lots:
		zones.append([lead_len + float(lot[0]) - t0, lead_len + float(lot[1]) - t0, StreetLevels.KERB_LOW, FLARE_M])
	var seen := {}
	var used := {}
	for p in pts:
		seen[_cell(p)] = true
	for cell in seen:
		for d in _drives.get(cell, []):
			var at := _project(pts, ls, d[0])
			if at[1] < NEAR_M and not used.has(["d", d[0]]):
				used[["d", d[0]]] = true
				zones.append([at[0] - float(d[2]) * 0.5, at[0] + float(d[2]) * 0.5, StreetLevels.KERB_LOW, FLARE_M])
		for r in _ramps.get(cell, []):
			var at := _project(pts, ls, r[0])
			if at[1] < NEAR_M and not used.has(["r", r[0]]):
				used[["r", r[0]]] = true
				zones.append([at[0] - float(r[2]) * 0.5, at[0] + float(r[2]) * 0.5, StreetLevels.ROAD, RAMP_FLARE_M])
				var along: Vector2 = Vector2(r[1]).orthogonal()
				run["ramps"].append([at[2], along, float(r[2]), float(r[3]), _out_at(run, ls, at[0])])
	var reds: Array = []
	for cell in seen:
		for h in _hydrants.get(cell, []):
			var at := _project(pts, ls, h)
			if at[1] < HYDRANT_M and not used.has(["h", h]):
				used[["h", h]] = true
				reds.append([at[0] - RED_M, at[0] + RED_M])
	# every zone and red edge becomes a point of the run, so heights and colours change exactly there
	var marks := PackedFloat32Array()
	for z in zones:
		for m in [z[0] - z[3], z[0], z[1], z[1] + z[3]]:
			marks.append(m)
	for r in reds:
		marks.append(r[0])
		marks.append(r[1])
	_insert(run, marks)
	pts = run["pts"]
	ls = _lengths(pts)
	var h := PackedFloat32Array()
	var zone := PackedByteArray()
	for j in pts.size():
		var y := StreetLevels.KERB
		var inz := 0
		for z in zones:
			var t := ls[j]
			var dz := maxf(float(z[0]) - t, t - float(z[1]))   # <= 0 inside
			if dz < float(z[3]) + 0.001:
				inz = 1
				y = minf(y, lerpf(float(z[2]), StreetLevels.KERB, clampf(dz / float(z[3]), 0.0, 1.0)))
		h.append(y)
		zone.append(inz)
	var red := PackedByteArray()
	for j in pts.size() - 1:
		var mid := (ls[j] + ls[j + 1]) * 0.5
		red.append(1 if reds.any(func(r: Array) -> bool: return mid > float(r[0]) and mid < float(r[1])) else 0)
	run["h"] = h
	run["zone"] = zone
	run["red"] = red
	if run["tier"] == "art":   # a metered space every METER_M along the straight, clear of drops, reds and ends
		var t := METER_M * 0.5
		while t < ls[ls.size() - 1] - 3.0:
			var clear := t > 3.0 and not zones.any(func(z: Array) -> bool: return t > float(z[0]) - float(z[3]) - 1.0 and t < float(z[1]) + float(z[3]) + 1.0) \
				and not reds.any(func(r: Array) -> bool: return t > float(r[0]) and t < float(r[1]))
			if clear:
				var a := _at(pts, ls, t)
				var k: int = a[1]
				run["meters"].append([a[0], (pts[k + 1] - pts[k]).normalized(), (run["out"][k] as Vector2).lerp(run["out"][k + 1], 0.5).normalized()])
			t += METER_M

## Where `p` falls along `pts`: [distance along, distance off, the point on the line].
static func _project(pts: PackedVector2Array, ls: PackedFloat32Array, p: Vector2) -> Array:
	var best := [0.0, INF, p]
	for k in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
		var d := q.distance_to(p)
		if d < best[1]:
			best = [ls[k] + pts[k].distance_to(q), d, q]
	return best

static func _out_at(run: Dictionary, ls: PackedFloat32Array, t: float) -> Vector2:
	var a := _at(run["pts"], ls, t)
	return (run["out"][a[1]] as Vector2).lerp(run["out"][a[1] + 1], 0.5).normalized()

## Adds a point at each distance in `marks` (inside the run), its normal blended from its neighbours.
static func _insert(run: Dictionary, marks: PackedFloat32Array) -> void:
	var pts: PackedVector2Array = run["pts"]
	var nrm: PackedVector2Array = run["out"]
	var ls := _lengths(pts)
	var total := ls[ls.size() - 1]
	var want := []
	for m in marks:
		if m > 0.02 and m < total - 0.02:
			want.append(m)
	if want.is_empty():
		return
	want.sort()
	var np := PackedVector2Array([pts[0]])
	var nn := PackedVector2Array([nrm[0]])
	var w := 0
	for k in pts.size() - 1:
		while w < want.size() and float(want[w]) < ls[k + 1] - 0.02:
			var t: float = want[w]
			if t > ls[k] + 0.02:
				var f := (t - ls[k]) / maxf(ls[k + 1] - ls[k], 0.0001)
				np.append(pts[k].lerp(pts[k + 1], f))
				nn.append(nrm[k].lerp(nrm[k + 1], f).normalized())
			w += 1
		np.append(pts[k + 1])
		nn.append(nrm[k + 1])
	run["pts"] = np
	run["out"] = nn
