"""MP2: the real LA street cross-section, derived from the MP1 widths.

MP1 gave every road a roadway width ("w") and one "side" figure per side. A real
LA street is not one blank strip there: from the kerb outwards it is

    kerb (6 in lip) | parkway (grass/dirt, street trees) | concrete sidewalk | lot

Sidewalk paving is 5 ft (1.5 m) on local streets and 8-10 ft on commercial
corridors; the parkway is whatever is left. Where that leftover is under
MIN_PARKWAY the whole side is paved kerb to lot line, which is what downtown and
most commercial frontage actually looks like; downtown is always full-width.

Discrete features on that band:
  wells   tree wells in the parkway, WELL_SPACING_M apart (LA plants street
          trees 20-30 ft apart), skipped at corners, driveways and buildings.
          MP5 puts the trees in them.
  aprons  driveway cuts: concrete crossing the band from the kerb to the lot,
          one per building front, sized by what the building is. Buildings whose
          door faces an alley get the narrow garage apron - LA houses garage off
          the alley. (MP4 will redo these off real parcel lines.)
  ramps   kerb ramps at both ends of every crosswalk, which is where LA puts
          them (one per crossing direction, not one per corner).

Nothing here changes where anyone may walk: the parkway and the sidewalk are
both inside the public zone the navmesh already has.

Usage: python3 -I street_section.py <city_v1.json> <buildings_v1.json> <public_v1.json> <out section_v1.json>
"""
import json
import math
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

# Major corridors and anything fronting commercial or industrial ground: paved kerb to
# lot line, with tree pits cut into the paving. Everywhere else: parkway + narrow walk.
PAVED_CLS = {"primary", "secondary", "primary_link", "secondary_link"}
PAVED_AREAS = ("commercial", "industrial", "downtown")
WALK_BY_CLS = {"tertiary": 2.4}
WALK_DEFAULT = 1.5        # LA residential sidewalk: 5 ft
MIN_PARKWAY = 1.2         # less than this left over -> pave the whole side
MIN_PIT_WALK = 1.8        # no tree pit in paving narrower than this: it would block the walk
KERB_M = 0.15             # kerb lip, drawn at the roadway edge

WELL_SPACING_M = 9.0
WELL_R = 0.6              # 4x4 ft tree well
WELL_CLEAR_M = 3.0        # keep wells this far from crosswalk ends and aprons
ROADWAY_CLEAR_M = 0.3     # and this far outside any roadway edge
BLD_CLEAR_M = 0.3         # and this far off a wall

APRON_W = {"house": 3.0, "garage": 3.0, "apartments": 4.5, "commercial": 6.0, "civic": 6.0, "industrial": 8.0}
APRON_W_DEFAULT = 3.5
APRON_ALLEY_W = 3.0
APRON_REACH_M = 12.0      # how far a door may be from its road and still get a driveway
APRON_MIN_GAP_M = 4.0     # two driveways closer than this are one driveway
REAL_REACH_M = 30.0       # how far from a street centre line a mapped lane may end and still meet it
APRON_MIN_LEN = 2.0       # shorter than this is not a driveway, just a kerb cut
APRON_TIERS = ("art", "res", "alley", "svc", "hill")

RAMP_W = 1.2              # LA kerb ramp: 4 ft min
RAMP_LEN = 1.5
RAMP_MIN_GAP_M = 1.5
RAMP_REACH_M = 22.0       # a crosswalk end is at most this far from the kerb it serves


def road_lines(city):
    return [(r, LineString(r["pts"])) for r in city["roads"] if float(r.get("side", 0.0)) > 0.0 and len(r["pts"]) >= 2]


def paved_areas(city):
    polys = [Polygon(a["poly"]).buffer(0) for a in city["areas"] if a["kind"] in PAVED_AREAS]
    return (STRtree(polys) if polys else None), polys


def split_side(road, mid, area_tree, area_polys):
    """side -> (sidewalk paving, parkway) per side, metres."""
    side = float(road.get("side", 0.0))
    if side <= 0.0:
        return 0.0, 0.0
    if road.get("cls", "") in PAVED_CLS:
        return side, 0.0
    if area_tree is not None and any(area_polys[k].contains(mid) for k in area_tree.query(mid)):
        return side, 0.0
    walk = min(side, WALK_BY_CLS.get(road.get("cls", ""), WALK_DEFAULT))
    park = side - walk
    return (side, 0.0) if park < MIN_PARKWAY else (walk, park)


def unit(a, b):
    d = (b[0] - a[0], b[1] - a[1])
    n = math.hypot(*d) or 1.0
    return (d[0] / n, d[1] / n)


class Grid:
    """Point set with a 'nothing else within r' test, bucketed so it stays linear."""

    def __init__(self, cell):
        self.cell = cell
        self.cells = {}

    def free(self, x, y, r):
        key = (int(x // self.cell), int(y // self.cell))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for px, py in self.cells.get((key[0] + dx, key[1] + dy), ()):
                    if math.hypot(px - x, py - y) < r:
                        return False
        return True

    def add(self, x, y):
        key = (int(x // self.cell), int(y // self.cell))
        self.cells.setdefault(key, []).append((x, y))


def band_rect(c, d, w, length):
    """The ground a driveway covers: from the kerb outwards across the band."""
    px, py = -d[1] * w / 2, d[0] * w / 2
    far = (c[0] + d[0] * length, c[1] + d[1] * length)
    return Polygon([(c[0] + px, c[1] + py), (far[0] + px, far[1] + py), (far[0] - px, far[1] - py), (c[0] - px, c[1] - py)])


def clear_run(c, d, w, full, bld_tree, bld_polys):
    """How far out from the kerb the driveway can run before it hits a wall.

    A house set back from the street gets the full band; one built closer gets a
    shorter apron; one built out to the kerb (or wedged between two neighbours
    with no gap) gets none.
    """
    length = full
    while length >= APRON_MIN_LEN:
        rect = band_rect(c, d, w, length)
        if not any(bld_polys[k].intersects(rect) for k in bld_tree.query(rect)):
            return length
        length -= 0.5
    return None


def real_aprons(city, lines, tree, section, grid):
    """A kerb cut where each mapped driveway, parking aisle or drive-through meets a street."""
    out = []
    for r in city["roads"]:
        if r["tier"] not in ("drive", "aisle"):
            continue
        for end in (Point(r["pts"][0]), Point(r["pts"][-1])):
            near = [k for k in tree.query(end.buffer(REAL_REACH_M)) if lines[k][0]["tier"] in ("art", "res", "hill")]
            if not near:
                continue
            k = min(near, key=lambda j: lines[j][1].distance(end))
            road, ln = lines[k]
            half = float(road["w"]) / 2
            sec = section[road["id"]]
            if ln.distance(end) > half + sec["walk"] + sec["park"] + 3.0:
                continue
            on = ln.interpolate(ln.project(end))
            if on.distance(end) < 0.01:
                continue
            nx, ny = unit((on.x, on.y), (end.x, end.y))   # outward = towards the lane
            cx, cy = on.x + nx * half, on.y + ny * half
            if not grid.free(cx, cy, APRON_MIN_GAP_M):
                continue
            grid.add(cx, cy)
            out.append({"c": [round(cx, 1), round(cy, 1)], "dir": [round(nx, 3), round(ny, 3)],
                        "w": round(min(float(r["w"]) + 1.0, 12.0), 1), "len": round(sec["walk"] + sec["park"] + 0.5, 1)})
    print("  driveway cuts where a mapped driveway or lot lane meets the street: %d" % len(out))
    return out


def aprons(city, blds, bld_tree, bld_polys, lines, section):
    """One driveway cut per building front, on the road its door faces."""
    tree = STRtree([ln for _, ln in lines])
    grid = Grid(APRON_MIN_GAP_M * 2)
    out = real_aprons(city, lines, tree, section, grid)   # MR5: surveyed driveways first; guesses only where there are none
    for b in blds:
        if "door" not in b:
            continue
        door = Point(b["door"])
        near = [k for k in tree.query(door.buffer(APRON_REACH_M)) if lines[k][0]["tier"] in APRON_TIERS]
        if not near:
            continue
        k = min(near, key=lambda j: lines[j][1].distance(door))
        road, ln = lines[k]
        if ln.distance(door) > APRON_REACH_M:
            continue
        s = ln.project(door)
        on = ln.interpolate(s)
        ahead = ln.interpolate(min(ln.length, s + 1.0))
        if ahead.distance(on) < 0.01:
            continue
        dx, dy = unit((on.x, on.y), (ahead.x, ahead.y))
        nx, ny = -dy, dx
        if (door.x - on.x) * nx + (door.y - on.y) * ny < 0:   # outward = towards the door
            nx, ny = -nx, -ny
        sec = section[road["id"]]
        half = float(road["w"]) / 2
        cx, cy = on.x + nx * half, on.y + ny * half
        if not grid.free(cx, cy, APRON_MIN_GAP_M):
            continue
        w = APRON_ALLEY_W if road["tier"] in ("alley", "svc") else APRON_W.get(b["kind"], APRON_W_DEFAULT)
        length = clear_run((cx, cy), (nx, ny), w, sec["walk"] + sec["park"] + 0.5, bld_tree, bld_polys)
        if length is None:   # built out to the kerb, or no gap wide enough: no driveway here
            continue
        grid.add(cx, cy)
        out.append({"c": [round(cx, 1), round(cy, 1)], "dir": [round(nx, 3), round(ny, 3)],
                    "w": round(min(w, 12.0), 1), "len": round(length, 1)})
    return out


def ramps(crosswalks, lines):
    """A kerb ramp at each end of each crosswalk: on the kerb, running up onto the band.

    A crosswalk is stored sidewalk to sidewalk, so its ends lie at the lot line;
    the ramp belongs at the kerb of the street being crossed on that side.
    """
    tree = STRtree([ln for _, ln in lines])
    grid = Grid(RAMP_MIN_GAP_M * 2)
    out = []
    for cw in crosswalks:
        dx, dy = cw["dir"]
        px, py = -dy, dx
        cx, cy = cw["c"]
        half = float(cw["len"]) / 2
        for sign in (-1, 1):
            end = Point(cx + px * half * sign, cy + py * half * sign)
            best = None
            for k in tree.query(end.buffer(RAMP_REACH_M)):
                road, ln = lines[k]
                d = ln.distance(end)
                if d > RAMP_REACH_M or (best is not None and d >= best[0]):
                    continue
                s = ln.project(end)
                on, ahead = ln.interpolate(s), ln.interpolate(min(ln.length, s + 1.0))
                if ahead.distance(on) < 0.01:
                    on, ahead = ln.interpolate(max(0.0, s - 1.0)), on
                rx, ry = unit((on.x, on.y), (ahead.x, ahead.y))
                if abs(rx * dx + ry * dy) < 0.7:   # that is the cross street, not the one being crossed
                    continue
                best = (d, road, ln.interpolate(s))
            if best is None:
                continue
            _, road, on = best
            nx, ny = unit((on.x, on.y), (end.x, end.y))
            x, y = on.x + nx * float(road["w"]) / 2, on.y + ny * float(road["w"]) / 2
            if not grid.free(x, y, RAMP_MIN_GAP_M):
                continue
            grid.add(x, y)
            out.append({"c": [round(x, 1), round(y, 1)], "dir": [round(nx, 3), round(ny, 3)],
                        "w": RAMP_W, "len": RAMP_LEN})
    return out


def roadways(city):
    """Every roadway as a polygon: nothing may be planted inside one."""
    polys = [LineString(r["pts"]).buffer(float(r.get("w", 6.0)) / 2 + ROADWAY_CLEAR_M, cap_style=2)
             for r in city["roads"] if len(r["pts"]) >= 2]
    return STRtree(polys), polys


def wells(city, lines, section, bld_tree, bld_polys, blocked):
    """Tree wells down the parkway, or tree pits cut into paving, both sides."""
    road_tree, road_polys = roadways(city)
    out = []
    for road, ln in lines:
        sec = section[road["id"]]
        if ln.length < WELL_SPACING_M:
            continue
        if sec["park"] >= MIN_PARKWAY:
            off = float(road["w"]) / 2 + sec["park"] / 2   # parkway against the kerb, sidewalk outside it
        elif sec["walk"] >= MIN_PIT_WALK:
            off = float(road["w"]) / 2 + WELL_R + 0.3      # pit cut into the paving, against the kerb
        else:
            continue
        steps = int(ln.length // WELL_SPACING_M)
        for i in range(1, steps):
            at = i * WELL_SPACING_M
            p = ln.interpolate(at)
            q = ln.interpolate(min(ln.length, at + 1.0))
            dx, dy = unit((p.x, p.y), (q.x, q.y))
            for sign in (-1, 1):
                x, y = p.x - dy * off * sign, p.y + dx * off * sign
                if not blocked.free(x, y, WELL_CLEAR_M):
                    continue
                pt = Point(x, y)
                if any(bld_polys[k].distance(pt) < WELL_R + BLD_CLEAR_M for k in bld_tree.query(pt.buffer(WELL_R + BLD_CLEAR_M))):
                    continue
                # a junction corner, or a street running alongside: the well would stand in traffic
                if any(road_polys[k].contains(pt) for k in road_tree.query(pt)):
                    continue
                out.append([round(x, 1), round(y, 1)])
    return out


def main(city_path, bld_path, pub_path, dst):
    city = json.load(open(city_path))
    blds = json.load(open(bld_path))["buildings"]
    pub = json.load(open(pub_path))
    bld_polys = [Polygon(b["poly"]).buffer(0) for b in blds]
    bld_tree = STRtree(bld_polys)
    lines = road_lines(city)
    area_tree, area_polys = paved_areas(city)
    section = {}
    for road, ln in lines:
        walk, park = split_side(road, ln.interpolate(0.5, normalized=True), area_tree, area_polys)
        section[road["id"]] = {"walk": round(walk, 2), "park": round(park, 2)}
    cuts = aprons(city, blds, bld_tree, bld_polys, lines, section)
    rmp = ramps(pub.get("crosswalks", []), lines)
    blocked = Grid(WELL_CLEAR_M * 2)
    for f in cuts + rmp:
        blocked.add(f["c"][0], f["c"][1])
    pits = wells(city, lines, section, bld_tree, bld_polys, blocked)
    json.dump({"format": "ganstoid.section", "version": 1, "city": city["id"], "kerb_m": KERB_M, "well_r": WELL_R,
               "roads": section, "wells": pits, "aprons": cuts, "ramps": rmp},
              open(dst, "w"), separators=(",", ":"))
    report(lines, section, pits, cuts, rmp, dst)


def report(lines, section, pits, cuts, rmp, dst):
    paved = parked = 0.0
    for road, ln in lines:
        if section[road["id"]]["park"] == 0.0:
            paved += ln.length
        else:
            parked += ln.length
    total = paved + parked or 1.0
    print("wrote %s" % dst)
    print("  streets with a sidewalk: %d (%.1f km)" % (len(lines), total / 1000))
    print("  with a parkway strip: %.1f%% of that length, paved kerb-to-lot: %.1f%%" % (100 * parked / total, 100 * paved / total))
    print("  tree wells %d, driveway cuts %d, kerb ramps %d" % (len(pits), len(cuts), len(rmp)))


if __name__ == "__main__":
    main(*sys.argv[1:5])
