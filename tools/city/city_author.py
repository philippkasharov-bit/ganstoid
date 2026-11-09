"""Ganstoid city concept v5.1: AUTHORED arterial skeleton (continuous, ~1 mi apart, natural
bends, every arterial ends on a freeway interchange, another arterial, or the map edge
= future expansion). Local streets are generated INSIDE each superblock and clipped to
it, so they always end exactly on a road. Locals are slightly irregular on purpose."""
import math
import random

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy.ndimage import gaussian_filter
from shapely.geometry import LineString, MultiLineString, Point, Polygon, box
from shapely.ops import nearest_points, polygonize, unary_union

import sys
OUT_DIR = (sys.argv[1] if len(sys.argv) > 1 else ".") + "/"
S, OUT = 2800, 1400
random.seed(3)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
TILT = math.tan(math.radians(6))


def spline(pts, n=14):
    p = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = map(np.array, p[i - 1:i + 3])
        for t in np.linspace(0, 1, n, endpoint=False):
            out.append(tuple(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)))
    out.append(tuple(pts[-1]))
    return out


def lines_of(g):
    if g.is_empty:
        return []
    if g.geom_type == "LineString":
        return [list(g.coords)]
    if g.geom_type in ("MultiLineString", "GeometryCollection"):
        out = []
        for h in g.geoms:
            out += lines_of(h)
        return out
    return []


# ---------------- terrain ----------------
def band(x):
    t = 0.525 + 0.012 * math.sin(x * 17) + 0.008 * math.sin(x * 41 + 1)
    b = 0.685 + 0.02 * math.sin(x * 9 + 2) + 0.01 * math.sin(x * 29)
    if x > 0.70:
        k = min(1.0, (x - 0.70) / 0.12)
        mid = (t + b) / 2
        t, b = t + k * (mid - t), b - k * (b - mid)
    return t, b


HX = np.linspace(0, 0.82, 140)
HILLS = Polygon([(x, band(x)[0]) for x in HX] + [(x, band(x)[1]) for x in HX[::-1]])
MTN = Polygon([(0.68, 0), (1, 0), (1, 0.175)])
PARK = Polygon([(x, band(x)[0] + 0.004) for x in np.linspace(0.0, 0.24, 30)] + [(x, band(x)[1] - 0.004) for x in np.linspace(0.24, 0.0, 30)])
AIRFIELD = box(0.38, 0.14, 0.47, 0.27)
BASIN = Point(0.33, 0.455).buffer(1, 32)
BASIN = Polygon([(0.33 + 0.055 * x * 1, 0.455 + 0.03 * y) for x, y in [((c - 0.33), (d - 0.455)) for c, d in []]]) if False else \
    Polygon([(0.33 + 0.055 * math.cos(t), 0.455 + 0.03 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 48)])
DT_C = (0.735, 0.80)

FWY = {
    "Valley Fwy": [(0, 0.505), (0.2, 0.498), (0.4, 0.507), (0.6, 0.500), (0.70, 0.505), (0.78, 0.535), (0.805, 0.60), (0.785, 0.68), (0.745, 0.76)],
    "Pass Fwy": [(0.30, 0), (0.30, 0.3), (0.305, 0.5), (0.29, 0.6), (0.31, 0.7), (0.32, 1.0)],
    "Diagonal Fwy": [(0.62, 0.502), (0.57, 0.35), (0.52, 0.18), (0.47, 0.0)],
    "River Fwy": [(0.54, 0), (0.75, 0.20), (0.915, 0.37), (0.90, 0.50), (0.862, 0.62), (0.858, 0.78), (0.855, 1.0)],
    "Foothill Fwy": [(0.68, 0), (0.85, 0.095), (1, 0.175)],
    "Crosstown Fwy": [(0, 0.93), (0.3, 0.935), (0.6, 0.925), (0.70, 0.89), (0.80, 0.872), (1, 0.872)],
    "Port Fwy": [(0.745, 0.76), (0.755, 0.86), (0.76, 1.0)],
}
FWY_L = {k: LineString(spline(v, 24)) for k, v in FWY.items()}
RIVER = LineString(spline([(0.985, 0.27), (0.95, 0.38), (0.918, 0.50), (0.902, 0.62), (0.905, 0.75), (0.897, 0.88), (0.892, 1.0)], 24))
RIVER_ZONE = unary_union([RIVER.buffer(0.015), RIVER.offset_curve(-0.03).buffer(0.017)])
FWY_ALL = unary_union(list(FWY_L.values()))
FWY_ZONE = FWY_ALL.buffer(0.009)
BORDER = box(0, 0, 1, 1)


def cross(line_pts, target):
    g = LineString(line_pts).intersection(target)
    if g.is_empty:
        return None
    if g.geom_type == "Point":
        return (g.x, g.y)
    return (g.geoms[0].x, g.geoms[0].y)


# ---------------- AUTHORED arterial skeleton ----------------
ART = []   # list of point lists (control points); splined later
RF, FF = FWY_L["River Fwy"], FWY_L["Foothill Fwy"]
PERP = (0.64, -0.77)   # direction across the foothill grid (perpendicular to River Fwy)

# valley E-W boulevards: cross the River Fwy, then bend to run across the foothill grid
for y in (0.05, 0.15, 0.25, 0.35):
    c = cross([(0, y), (1, y)], RF)
    far = (c[0] + PERP[0] * 0.4, c[1] + PERP[1] * 0.4)
    end = cross([c, far], unary_union([FF, BORDER.exterior]))
    ART.append([(0, y), (c[0] - 0.05, y), (c[0] - 0.01, y), (c[0] + PERP[0] * 0.025, c[1] + PERP[1] * 0.025 + 0.004), end])
ART.append([(0, 0.45), (0.5, 0.45), (0.95, 0.448), (1, 0.447)])   # crosses River Fwy + river into industry

# valley N-S boulevards
CANYON = {0.15: 0.15, 0.40: 0.40, 0.60: 0.60}
for x in (0.05, 0.15, 0.25, 0.40, 0.50, 0.60, 0.70, 0.80):
    top = (x, 0.0) if x <= 0.52 else cross([(x, 0), (x, 0.5)], RF)
    if x in CANYON:   # continues through the hills as a canyon road, then south
        t, b = band(x)
        pts = [top, (x, 0.30), (x, t - 0.03)]
        rng = np.random.default_rng(int(x * 100))
        for k, yy in enumerate(np.linspace(t + 0.01, b - 0.01, 5)):
            pts.append((x + 0.012 * math.sin(k * 1.7 + x * 20) + rng.normal(0, 0.003), yy))
        yb = b + 0.03
        if x < 0.52:   # Westside tilt
            pts += [(x, yb), (x + TILT * (1 - yb), 1.0)]
        else:
            pts += [(x, yb), (x - 0.01, 0.80), (x - 0.012, 1.0)]
        ART.append(pts)
    else:
        bottom = cross([(x, 0.3), (x, 0.7)], FWY_L["Valley Fwy"])
        ART.append([top, (x, (top[1] + bottom[1]) / 2), bottom])

# foothill grid spine, parallel to both freeways, halfway between them
spine = []
for x in np.linspace(0.58, 0.90, 8):
    yr = cross([(x, -0.1), (x, 0.6)], RF)
    yf = cross([(x, -0.1), (x, 0.6)], FF)
    yr = yr[1] if yr else 0.0
    yf = yf[1] if yf else 0.0
    spine.append((x, (yr + yf) / 2))
ART.append(spine)

# hill-foot boulevard on the south side, ends at Valley Fwy interchange
SUNSET = [(x, band(x)[1] + 0.014) for x in np.linspace(0, 0.74, 14)] + [(0.775, 0.68), (0.79, 0.655)]
ART.append(SUNSET)
SB = LineString(spline(SUNSET))


def on_sunset(x):
    return cross([(x, 0.6), (x, 0.8)], SB)


# Westside / midtown N-S (non-canyon), start on the hill-foot boulevard
for x in (0.05, 0.25, 0.48, 0.68):
    s = on_sunset(x)
    if x < 0.52:
        ART.append([s, (x + TILT * (1 - s[1]), 1.0)])
    else:
        ART.append([s, (x, 0.80), (x - 0.004, 1.0)])

# Westside -> Midtown E-W boulevards (bend from -6 deg to flat), through downtown at 36 deg
ART.append([(0, 0.80), (0.26, 0.773), (0.52, 0.745), (0.62, 0.745), (0.67, 0.752), DT_C, (0.80, 0.835), (0.87, 0.822), (1, 0.80)])
ART.append([(0, 0.885), (0.26, 0.858), (0.52, 0.83), (0.64, 0.832), (0.71, 0.842), (0.752, 0.855)])
ART.append([(0, 0.985), (0.5, 0.975), (0.86, 0.968), (1, 0.962)])
ART.append([(0.06, 0.984), (0.30, 0.85), (0.50, 0.738), on_sunset(0.53)])          # Westside diagonal
ART.append([(0.79, 0.735), DT_C, (0.70, 0.848)])                                      # downtown cross axis
# industry
ART.append([cross([(0.80, 0.62), (1, 0.62)], RF), (0.93, 0.62), (1, 0.618)])
ART.append([(0.955, 0.447), (0.958, 0.62), (0.952, 0.80), (0.95, 1.0)])

ART_L = [LineString(spline(a)) for a in ART]


def snap_to_freeway(line):
    """An arterial that stops near a freeway ends exactly on it (interchange), never short of it."""
    pts = list(line.coords)
    for end in (0, -1):
        q = Point(pts[end])
        if min(q.x, q.y, 1 - q.x, 1 - q.y) < 0.003:
            continue
        f, _ = nearest_points(FWY_ALL, q)
        if 0 < q.distance(f) < 0.015:
            pts[end] = (f.x, f.y)
    return LineString(pts)


ART_L = [snap_to_freeway(a) for a in ART_L]
ART_U = unary_union(ART_L)

# ---------------- superblocks ----------------
BARRIERS = [HILLS.exterior, RIVER_ZONE.boundary, AIRFIELD.exterior, BASIN.exterior, MTN.exterior, BORDER.exterior]
faces = list(polygonize(unary_union(ART_L + list(FWY_L.values()) + BARRIERS)))
BLOCK = unary_union([FWY_ZONE, RIVER_ZONE, HILLS.buffer(0.004), MTN, AIRFIELD.buffer(0.005), BASIN.buffer(0.005)])
ART_BUF = ART_U.buffer(0.0018)
EDGE_EXCL = BORDER.exterior.buffer(0.002)


def field(p):
    cx = sy = 0.0
    for c, r, ang, w in [((0.25, 0.25), 0.45, 0, 1.0), ((0.86, 0.17), 0.13, 40, 1.6), ((0.25, 0.84), 0.30, -6, 1.2),
                         ((0.62, 0.82), 0.10, 0, 1.0), (DT_C, 0.07, 36, 3.0), ((0.95, 0.70), 0.14, 0, 1.2)]:
        k = w * math.exp(-((p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2) / (r * r))
        cx += k * math.cos(math.radians(2 * ang))
        sy += k * math.sin(math.radians(2 * ang))
    return 0.5 * math.atan2(sy, cx + 0.05)


roads = {"res": [], "alley": [], "svc": [], "hill": [], "edge": [], "path": []}
dead_ends = []


def family(face, theta, spacing, jitter, wobble, phase, freq=90):
    """Parallel streets across a superblock. Each street gets its OWN small angle
    and its own random bends (no shared sine wave), so blocks look organic."""
    c = face.centroid
    R = math.dist(face.bounds[:2], face.bounds[2:]) / 2 + 0.01
    out = []
    off = -R + spacing * random.uniform(0.3, 0.7)
    while off < R:
        a = theta + (random.gauss(0, 0.012) if wobble > 0 else 0.0)
        d = (math.cos(a), math.sin(a))
        n = (-d[1], d[0])
        step = 0.03 if wobble > 0.003 else 0.06
        ts = np.arange(-R, R + step, step)
        ctrl = []
        for t in ts:
            o = off + (random.gauss(0, wobble) if wobble > 0 else 0.0)
            ctrl.append((c.x + d[0] * t + n[0] * o, c.y + d[1] * t + n[1] * o))
        out.append((off, LineString(spline(ctrl, 6) if wobble > 0 else ctrl)))
        off += spacing * random.uniform(1 - jitter, 1 + jitter)
    return out


def spaced(lines, face, min_gap, theta):
    """Drop streets that come closer than min_gap to an already-kept parallel street,
    or that hug the block edge: no sliver blocks."""
    kept = []
    edge = face.boundary
    for off, ln in lines:
        inner = ln.intersection(face)
        if inner.is_empty:
            continue
        samples = [inner.interpolate(t, normalized=True) for t in np.linspace(0.2, 0.8, 7)] if inner.length > 0 else []
        nx, ny = -math.sin(theta) * min_gap, math.cos(theta) * min_gap
        hugging = sum(1 for q in samples if LineString([(q.x - nx, q.y - ny), (q.x + nx, q.y + ny)]).intersects(edge))
        if samples and hugging > len(samples) / 2:
            continue   # runs alongside the block edge: would make a sliver block
        if any(inner.distance(k) < min_gap for _, k in kept):
            continue
        kept.append((off, inner))
    return kept


def _jog(pts, shift):
    """Shift the rest of a street sideways from a random point: an LA-style jog."""
    if len(pts) < 4:
        return pts
    k = random.randint(1, len(pts) - 2)
    return pts[:k] + [(x + shift[0], y + shift[1]) for x, y in pts[k:]]


def purposeful_breaks(f2, mains, th, sp, curvy, tier, mains_u):
    """Break the grid ON PURPOSE: escape routes, old roads, hidden spots."""
    d = (math.cos(th), math.sin(th))
    n = (-d[1], d[0])
    ordered = sorted(mains, key=lambda m: m[0])
    for (_, a), (_, b) in zip(ordered, ordered[1:]):   # mid-block cut-throughs (escape routes)
        if a.length < 0.02 or random.random() > 0.35:
            continue
        qa = a.interpolate(random.uniform(0.25, 0.75), normalized=True)
        qb = nearest_points(b, qa)[0]
        if qa.distance(qb) > 2.5 * sp:
            continue
        pts = [(qa.x, qa.y), (qb.x, qb.y)]
        if random.random() < 0.5:                       # doglegged passage
            m1 = ((qa.x + qb.x) / 2, (qa.y + qb.y) / 2)
            j = random.choice((-1, 1)) * 0.004
            m2 = (m1[0] + d[0] * j, m1[1] + d[1] * j)
            qb2 = nearest_points(b, Point(m2))[0]
            pts = [(qa.x, qa.y), m1, m2, (qb2.x, qb2.y)]
        roads["path"].append(pts)
    if not curvy and f2.area > 0.003 and random.random() < 0.22:   # older road cutting across on a curve
        ring = f2.exterior
        p1 = ring.interpolate(random.uniform(0, ring.length))
        p2 = ring.interpolate((ring.project(p1) + ring.length * random.uniform(0.35, 0.65)) % ring.length)
        mid = ((p1.x + p2.x) / 2 + random.gauss(0, 0.012), (p1.y + p2.y) / 2 + random.gauss(0, 0.012))
        for piece in lines_of(LineString(spline([(p1.x, p1.y), mid, (p2.x, p2.y)], 12)).intersection(f2)):
            if LineString(piece).length > 0.01:
                roads[tier].append(piece)
    for _, a in mains:                                  # hidden courtyards: dead-end alley spurs
        if a.length > 0.03 and random.random() < 0.12:
            q = a.interpolate(random.uniform(0.2, 0.8), normalized=True)
            sg = random.choice((1, -1))
            e = (q.x + n[0] * 0.0045 * sg, q.y + n[1] * 0.0045 * sg)
            if f2.buffer(-0.002).contains(Point(e)) and (mains_u is None or not LineString([(q.x, q.y), e]).crosses(mains_u)):
                roads["alley"].append([(q.x, q.y), e])
                dead_ends.append(e)


for face in faces:
    p = face.representative_point()
    if HILLS.contains(p) or MTN.contains(p) or AIRFIELD.contains(p) or BASIN.contains(p) or RIVER_ZONE.contains(p):
        continue
    f2 = face.difference(BLOCK)
    if f2.is_empty or f2.area < 2e-5:
        continue
    th = field((p.x, p.y))
    dtk = math.dist((p.x, p.y), DT_C) < 0.075
    ind = p.x > 0.86 and p.y > 0.38
    old = p.y > 0.70 or (p.x > 0.58 and p.y < 0.36)
    tier = "svc" if ind else "res"
    # edge streets: where the superblock meets a freeway/river/hill instead of a boulevard
    for ln in lines_of(f2.boundary.difference(ART_BUF).difference(EDGE_EXCL)):
        if LineString(ln).length > 0.006:
            roads["edge"].append(ln)
    curvy = not dtk and not ind and not old and random.random() < 0.3
    sp = (0.006 if dtk else 0.015) * (2.0 if ind else 1)
    mains = spaced(family(f2, th, sp * (1.15 if curvy else 1), 0.10, 0.0 if dtk else (0.0025 if curvy else 0.0010), random.uniform(0, 6), 24 if curvy else 90), f2, sp * (0.5 if curvy else 0.65), th)
    main_geoms = []
    for off, ln in mains:
        for piece in lines_of(ln.intersection(f2)):
            if LineString(piece).length > 0.006:
                roads[tier].append(piece)
                main_geoms.append(LineString(piece))
        if old and not ind and not curvy and not dtk and random.random() < 0.5:
            alley = unary_union([LineString(q).offset_curve(sp * 0.5) for q in lines_of(ln) if len(q) > 1])
            for piece in lines_of(alley.intersection(f2.buffer(-0.002))):
                if LineString(piece).length > 0.01:
                    if LineString(piece).length > 0.04 and random.random() < 0.4:
                        j = random.choice((-1, 1)) * 0.0025
                        piece = _jog(piece, (-math.sin(th) * j, math.cos(th) * j))
                    roads["alley"].append(piece)
    mains_u = unary_union(main_geoms) if main_geoms else None
    crosses = spaced(family(f2, th + math.pi / 2, sp * (1 if dtk else (1.8 if curvy else 1.1)), 0.15, 0.0 if dtk else 0.0008, random.uniform(0, 6)), f2, sp * (0.7 if dtk else 0.75), th + math.pi / 2)
    for off, ln in crosses:
        for piece in lines_of(ln.intersection(f2)):
            L = LineString(piece)
            if L.length < 0.006:
                continue
            r = random.random()
            if r < 0.12 and mains_u is not None and not dtk:
                # stops at a local street partway: T-junction inside the block
                hits = L.intersection(mains_u)
                pts = [h for h in getattr(hits, "geoms", [hits]) if h.geom_type == "Point"]
                if len(pts) >= 2:
                    cut = random.choice(pts[: max(1, len(pts) - 1)])
                    part = LineString(piece).project(cut)
                    seg = [q for q in piece if LineString(piece).project(Point(q)) <= part] + [(cut.x, cut.y)]
                    if len(seg) > 1:
                        roads[tier].append(seg)
                        continue
            if not dtk and random.random() < 0.25:
                j = random.choice((-1, 1)) * 0.002
                piece = _jog(piece, (math.cos(th) * j, math.sin(th) * j))
            roads[tier].append(piece)
    # occasional cul-de-sac stub off a residential street
    if not dtk and not ind:
        for g in main_geoms:
            if g.length > 0.03 and random.random() < (0.6 if curvy else 0.2):
                q = g.interpolate(random.uniform(0.2, 0.8), normalized=True)
                d = (math.cos(th + math.pi / 2), math.sin(th + math.pi / 2))
                sg = random.choice((1, -1))
                e = (q.x + d[0] * 0.005 * sg, q.y + d[1] * 0.005 * sg)
                if f2.buffer(-0.002).contains(Point(e)) and not LineString([(q.x, q.y), e]).crosses(mains_u):
                    roads[tier].append([(q.x, q.y), e])
                    dead_ends.append(e)
        purposeful_breaks(f2, mains, th, sp, curvy, tier, mains_u)

# ---------------- hills: contour roads joined to canyon boulevards / edge streets ----------------
HF = gaussian_filter(np.random.default_rng(5).standard_normal((220, 220)), 9)
cs = plt.contour(np.linspace(0, 1, 220), np.linspace(0, 1, 220), HF / np.abs(HF).max(), levels=np.linspace(-0.7, 0.7, 12))
inner_hills = HILLS.buffer(-0.006)
CONNECT = unary_union([ART_U] + [LineString(e) for e in roads["edge"]])
for segs in cs.allsegs[::2]:
    for seg in segs:
        for piece in lines_of(LineString(seg).intersection(inner_hills).difference(ART_U.buffer(0.004))):
            L = LineString(piece)
            if L.length < 0.03:
                continue
            park = PARK.contains(L.centroid)
            if park:
                roads["hill"].append(("trail", piece))
                continue
            pts = list(piece)
            for end in (0, -1):
                q = Point(pts[end])
                a, b = nearest_points(CONNECT, q)
                if q.distance(a) < 0.03:
                    if end == 0:
                        pts.insert(0, (a.x, a.y))
                    else:
                        pts.append((a.x, a.y))
                else:
                    dead_ends.append(pts[end])
            roads["hill"].append(("hill", pts))

# ---------------- interchanges ----------------
ramps = []
for fl in FWY_L.values():
    for al in ART_L:
        x = fl.intersection(al)
        for pt in [h for h in getattr(x, "geoms", [x]) if not x.is_empty and h.geom_type == "Point"]:
            df = fl.project(pt)
            da = al.project(pt)
            for s1 in (-1, 1):
                f_pt = fl.interpolate(df + s1 * 0.018)
                for s2 in (-1, 1):
                    a_pt = al.interpolate(da + s2 * 0.010)
                    if s1 * s2 > 0:
                        ramps.append([(f_pt.x, f_pt.y), (a_pt.x, a_pt.y)])
fnames = list(FWY_L)
for i in range(len(fnames)):
    for j in range(i + 1, len(fnames)):
        x = FWY_L[fnames[i]].intersection(FWY_L[fnames[j]])
        for pt in [h for h in getattr(x, "geoms", [x]) if not x.is_empty and h.geom_type == "Point"]:
            A, B = FWY_L[fnames[i]], FWY_L[fnames[j]]
            for s1 in (-1, 1):
                for s2 in (-1, 1):
                    p1 = A.interpolate(A.project(pt) + s1 * 0.03)
                    p2 = B.interpolate(B.project(pt) + s2 * 0.03)
                    mid = ((p1.x + p2.x) / 2 * 0.6 + pt.x * 0.4, (p1.y + p2.y) / 2 * 0.6 + pt.y * 0.4)
                    ramps.append(spline([(p1.x, p1.y), mid, (p2.x, p2.y)], 8))

edge_arrows = []
for a in ART_L:
    for q in (a.coords[0], a.coords[-1]):
        if q[0] < 0.003 or q[0] > 0.997 or q[1] < 0.003 or q[1] > 0.997:
            edge_arrows.append(q)


# ---------------- render ----------------
def px(pts): return [(x * S, y * S) for x, y in pts]


def draw_line(d, pts, color, w, dash=None):
    p = px(pts)
    if len(p) < 2:
        return
    if dash is None:
        d.line(p, fill=color, width=int(w), joint="curve")
        return
    on, off = dash
    acc, state = 0.0, True
    for a, b in zip(p[:-1], p[1:]):
        seg = math.dist(a, b) or 1e-6
        t = 0.0
        while t < seg:
            step = min((on if state else off) - acc, seg - t)
            if state:
                f0, f1 = t / seg, (t + step) / seg
                d.line([(a[0] + (b[0] - a[0]) * f0, a[1] + (b[1] - a[1]) * f0), (a[0] + (b[0] - a[0]) * f1, a[1] + (b[1] - a[1]) * f1)], fill=color, width=int(w))
            t += step
            acc += step
            if acc >= (on if state else off):
                acc, state = 0.0, not state


ROT = Polygon([(0.54, 0), (0.68, 0), (1, 0.175), (1, 0.30), (0.915, 0.37)])
IND = Polygon([(0.915, 0.37), (1, 0.30), (1, 1), (0.855, 1), (0.858, 0.78), (0.862, 0.62), (0.90, 0.50)])
DT_BLOB = Polygon([(DT_C[0] + 0.068 * math.cos(t) * (1 + 0.1 * math.sin(3 * t)), DT_C[1] + 0.058 * math.sin(t) * (1 + 0.08 * math.cos(2 * t))) for t in np.linspace(0, 2 * math.pi, 48)])


def render(night):
    if not night:
        pal = dict(bg="#f1ebde", rot="#ede4d2", ind="#dcd8e2", hill="#e1e7d1", mtn="#c3cfb5", park="#c7dbb3", dt="#ddd0b6",
                   res="#b5ac99", edge="#b5ac99", hillr="#a89d82", svc="#a49eb2", alley="#b6ae9f", trail="#9b8357",
                   art="#fffaf0", artc="#b9a37a", front="#f0d7b3", fw="#f39a35", fwc="#9b5310", ramp="#e08a2c", riv="#c4cfd6", rivc="#9fb0ba", rail="#7d7468")
    else:
        pal = dict(bg="#151a26", rot="#141824", ind="#111420", hill="#0b0f14", mtn="#080b0f", park="#0b130d", dt="#221d22",
                   res="#3d4054", edge="#3d4054", hillr="#262a33", svc="#2a2d3e", alley="#07080b", trail="#1b1a17",
                   art="#f3a443", artc=None, front=None, fw="#ffc066", fwc="#3b2a14", ramp="#a7782f", riv="#090c12", rivc="#05070b", rail="#1d1c22")
    img = Image.new("RGB", (S, S), pal["bg"])
    d = ImageDraw.Draw(img)
    for poly, key in [(ROT, "rot"), (IND, "ind"), (HILLS, "hill"), (MTN, "mtn"), (PARK, "park"), (DT_BLOB, "dt"), (BASIN, "park")]:
        d.polygon(px(poly.exterior.coords), fill=pal[key])
    d.rectangle([0.38 * S, 0.14 * S, 0.47 * S, 0.27 * S], fill="#e4e0d4" if not night else "#10131c")
    d.line(px([(0.392, 0.16), (0.458, 0.25)]), fill="#8d8a84" if not night else "#3b3e4a", width=26)
    lit = Image.new("RGB", (S, S), "#000000")
    ld = ImageDraw.Draw(lit)
    if pal["front"]:
        for a in ART_L:
            draw_line(d, a.coords, pal["front"], 30)
    for pts in roads["alley"]:
        draw_line(d, pts, pal["alley"], 2, (6, 5) if not night else None)
    for pts in roads["svc"]:
        draw_line(d, pts, pal["svc"], 4)
    for kind, pts in roads["hill"]:
        draw_line(d, pts, pal["trail"] if kind == "trail" else pal["hillr"], 2 if kind == "trail" else 3, (5, 7) if kind == "trail" else None)
    for pts in roads["res"] + roads["edge"]:
        draw_line(d, pts, pal["res"], 3)
    for e in dead_ends:
        r = 0.0028 * S
        d.ellipse([e[0] * S - r, e[1] * S - r, e[0] * S + r, e[1] * S + r], fill=pal["res"])
    draw_line(d, RIVER.coords, pal["rivc"], 34)
    draw_line(d, RIVER.coords, pal["riv"], 22)
    for k in range(6):
        draw_line(d, RIVER.offset_curve(-0.022 - 0.004 * k).coords, pal["rail"], 3, (14, 6))
    for a in ART_L:
        if pal["artc"]:
            draw_line(d, a.coords, pal["artc"], 14)
        draw_line(d, a.coords, pal["art"], 10 if not night else 8)
        if night:
            draw_line(ld, a.coords, "#ff9a2e", 16)
    for r in ramps:
        draw_line(d, r, pal["ramp"], 5)
    for fl in FWY_L.values():
        draw_line(d, fl.coords, pal["fwc"], 30)
        draw_line(d, fl.coords, pal["fw"], 20)
        if night:
            draw_line(ld, fl.coords, "#ffb04a", 34)
    if night:
        rng = np.random.default_rng(3)
        for _ in range(2600):
            x, y = rng.uniform(0.66, 0.81), rng.uniform(0.74, 0.86)
            if DT_BLOB.contains(Point(x, y)):
                ld.ellipse([x * S - 3, y * S - 3, x * S + 3, y * S + 3], fill="#ffd27a")
        glow = lit.filter(ImageFilter.GaussianBlur(10))
        img = Image.fromarray(np.clip(np.array(img).astype(np.int16) + (np.array(glow) * 0.45).astype(np.int16), 0, 255).astype(np.uint8))
    return img.resize((OUT, OUT), Image.LANCZOS)


def label(d, xy, text, size=17, color="#3b3328", bold=True, halo=None):
    f = ImageFont.truetype(FONTB if bold else FONT, size)
    x, y = xy[0] * OUT - d.textlength(text, font=f) / 2, xy[1] * OUT
    if halo:
        for ox in (-2, 0, 2):
            for oy in (-2, 0, 2):
                d.text((x + ox, y + oy), text, font=f, fill=halo)
    d.text((x, y), text, font=f, fill=color)


day, night = render(False), render(True)
dd = ImageDraw.Draw(day)
halo = "#f4efe4"
for xy, t in [((0.17, 0.25), "VALLEY FLATS"), ((0.83, 0.17), "FOOTHILL GRID"), ((0.90, 0.05), "MOUNTAINS"),
              ((0.10, 0.60), "CANYON PARK (wild)"), ((0.48, 0.585), "THE HILLS"), ((0.20, 0.82), "WESTSIDE"),
              ((0.60, 0.785), "MIDTOWN"), ((0.735, 0.81), "DOWNTOWN"), ((0.95, 0.70), "RIVER"),
              ((0.95, 0.72), "INDUSTRIAL"), ((0.425, 0.205), "AIRFIELD"), ((0.33, 0.448), "BASIN PARK")]:
    label(dd, xy, t, 17, halo=halo)
for name, (x, y) in {"Valley Fwy": (0.11, 0.488), "Pass Fwy": (0.27, 0.36), "Diagonal Fwy": (0.555, 0.27),
                     "River Fwy": (0.66, 0.085), "Foothill Fwy": (0.86, 0.07), "Crosstown Fwy": (0.15, 0.942),
                     "Port Fwy": (0.80, 0.975)}.items():
    label(dd, (x, y), name, 13, "#7a3e08", True, halo=halo)
for q in edge_arrows:
    x, y = q[0] * OUT, q[1] * OUT
    dd.ellipse([x - 6, y - 6, x + 6, y + 6], fill="#2f7d8c")

nd = ImageDraw.Draw(night)
for e in dead_ends:
    nd.ellipse([e[0] * OUT - 2.5, e[1] * OUT - 2.5, e[0] * OUT + 2.5, e[1] * OUT + 2.5], fill="#ff4d4d")
cam_rng = np.random.default_rng(9)
for a in ART_L:
    L = a.length
    for t in np.arange(0, L, 0.02):
        p = a.interpolate(t)
        if HILLS.buffer(0.01).contains(p) or (p.x > 0.86 and p.y > 0.38):
            continue
        dtk = DT_BLOB.contains(p)
        if cam_rng.random() < (0.5 if dtk else 0.12):
            nd.rectangle([p.x * OUT - 3, p.y * OUT - 3, p.x * OUT + 3, p.y * OUT + 3], outline="#45e0ff", width=2)
for p in [(0.52, 0.60), (0.545, 0.615), (0.50, 0.62)]:
    nd.rectangle([p[0] * OUT - 3, p[1] * OUT - 3, p[0] * OUT + 3, p[1] * OUT + 3], outline="#45e0ff", width=2)
spots = []
for fl in FWY_L.values():
    for a in ART_L:
        x = fl.intersection(a)
        for pt in [h for h in getattr(x, "geoms", [x]) if not x.is_empty and h.geom_type == "Point"]:
            spots.append((pt.x, pt.y))
spots += [RIVER.offset_curve(-0.03).interpolate(t, normalized=True).coords[0] for t in np.linspace(0.05, 0.95, 7)]
for x, y in spots:
    nd.ellipse([x * OUT - 8, y * OUT - 8, x * OUT + 8, y * OUT + 8], outline="#b46cff", width=2)
nh = "#0d111b"
for xy, t in [((0.17, 0.25), "VALLEY FLATS"), ((0.48, 0.585), "THE HILLS (dark)"), ((0.735, 0.81), "DOWNTOWN"),
              ((0.95, 0.70), "INDUSTRIAL"), ((0.20, 0.82), "WESTSIDE"), ((0.10, 0.60), "CANYON PARK"), ((0.60, 0.785), "MIDTOWN")]:
    label(nd, xy, t, 16, "#d9d4c8", halo=nh)
label(nd, (0.525, 0.635), "gated enclave", 12, "#9fe9ff", False, halo=nh)

W, Hh = OUT * 2 + 30, OUT + 70 + 190
canvas = Image.new("RGB", (W, Hh), "#1a1b20")
canvas.paste(day, (10, 60))
canvas.paste(night, (OUT + 20, 60))
c = ImageDraw.Draw(canvas)
tf = ImageFont.truetype(FONTB, 26)
c.text((20, 16), "GANSTOID — fixed city concept v5.1 (day road map)", font=tf, fill="#f2efe8")
c.text((OUT + 30, 16), "Night gameplay map — light, dead ends, cameras, dark spots", font=tf, fill="#f2efe8")
lf = ImageFont.truetype(FONT, 17)
y0 = OUT + 80
items = [("#f39a35", 10, "Freeway + interchange ramps"), ("#fffaf0", 7, "Boulevard (authored, ~1 mi apart)"),
         ("#b5ac99", 3, "Local street (irregular on purpose)"), ("#b6ae9f", 2, "Alley (older districts)"),
         ("#a89d82", 3, "Hill road + cul-de-sacs"), ("#a49eb2", 3, "Industrial service road"),
         ("#7d7468", 2, "Rail yards"), ("#c4cfd6", 8, "Dry concrete river channel"), ("dot", 0, "Boulevard continues into future expansion")]
for i, (col, w, txt) in enumerate(items):
    x, y = 30 + (i % 3) * 460, y0 + (i // 3) * 40
    if col == "dot":
        c.ellipse([x + 18, y + 4, x + 32, y + 18], fill="#2f7d8c")
    else:
        c.line([(x, y + 11), (x + 50, y + 11)], fill=col, width=w)
    c.text((x + 62, y), txt, font=lf, fill="#e6e2d8")
nx = OUT + 40
night_items = [("dot", "#ff4d4d", "Cul-de-sac (1 exit = trap)"), ("sq", "#45e0ff", "Camera (commercial, downtown, rich only)"),
               ("ring", "#b46cff", "Dark spot: underpass, rail yard"), ("line", "#ffb04a", "Lit: freeways, boulevards, downtown"),
               ("line", "#3d4054", "Dim: local streets"), ("line", "#555555", "Pitch dark: alleys, hills, yards")]
for i, (kind, col, txt) in enumerate(night_items):
    x, y = nx + (i % 2) * 680, y0 + (i // 2) * 40
    if kind == "dot":
        c.ellipse([x + 18, y + 4, x + 32, y + 18], fill=col)
    elif kind == "sq":
        c.rectangle([x + 16, y + 3, x + 34, y + 19], outline=col, width=3)
    elif kind == "ring":
        c.ellipse([x + 14, y + 1, x + 36, y + 21], outline=col, width=3)
    else:
        c.line([(x, y + 11), (x + 50, y + 11)], fill=col, width=6)
    c.text((x + 62, y), txt, font=lf, fill="#e6e2d8")
c.text((30, Hh - 34), "Concept only. All names fictional. Boulevards are hand-authored and continuous; local streets are generated inside each superblock and always end on a road.",
       font=ImageFont.truetype(FONT, 15), fill="#9a978f")
canvas.save(OUT_DIR + "ganstoid_city_v5_1.png")
print("ok faces", len(faces), "arterials", len(ART_L), {k: len(v) for k, v in roads.items()}, "cul-de-sacs", len(dead_ends))

# ---------------- C1 export: frozen city data for the game ----------------
import json, os
SIZE = 4096.0


def ex(pts, tol=0.0006):
    g = LineString(pts).simplify(tol)
    return [[round(x * SIZE, 1), round(y * SIZE, 1)] for x, y in g.coords]


def exp_poly(poly):
    return [[round(x * SIZE, 1), round(y * SIZE, 1)] for x, y in poly.simplify(0.0005).exterior.coords]


out_roads, n = [], 0


def add(tier, pts, name=None):
    global n
    if len(pts) < 2:
        return
    if tier == "res" and math.dist(pts[0], pts[-1]) < 1e-9 and LineString(pts).length < 0.05:
        return   # tiny closed loop left between barriers: unreachable, drop it
    for piece in lines_of(LineString(pts).intersection(BORDER)):
        if len(piece) < 2:
            continue
        n += 1
        r = {"id": "base:road_%05d" % n, "tier": tier, "pts": ex(piece)}
        if name:
            r["name"] = name
        out_roads.append(r)


for k, fl in FWY_L.items():
    add("fwy", list(fl.coords), k)
for r in ramps:
    add("ramp", r)
for a in ART_L:
    add("art", list(a.coords))
for t in ("res", "edge", "alley", "svc", "path"):
    for pts in roads[t]:
        add("res" if t == "edge" else t, pts)
for kind, pts in roads["hill"]:
    add(kind, pts)
_loops = [r for r in out_roads if r["tier"] == "res" and r["pts"][0] == r["pts"][-1]]
_rest = unary_union([LineString(r["pts"]) for r in out_roads if r not in _loops])
out_roads = [r for r in out_roads if r not in _loops or LineString(r["pts"]).distance(_rest) < 12.0]
print("dropped unreachable loops:", sum(1 for r in _loops if r not in out_roads))
# no two streets run side by side closer than PARALLEL_MIN_M: drop the shorter one
from shapely.strtree import STRtree
PARALLEL_MIN_M = 35.0


def _dir_at(g, t):
    a, b = g.interpolate(max(0.0, t - 5)), g.interpolate(min(g.length, t + 5))
    v = (b.x - a.x, b.y - a.y)
    n_ = math.hypot(*v) or 1
    return (v[0] / n_, v[1] / n_)


_g = [LineString(r["pts"]) for r in out_roads]
_tree = STRtree(_g)
_dropped = set()
for i in sorted(range(len(out_roads)), key=lambda k: _g[k].length):
    if out_roads[i]["tier"] not in ("res", "svc") or _g[i].length < 40:
        continue
    _m = _g[i].interpolate(0.5, normalized=True)
    if math.dist((_m.x / SIZE, _m.y / SIZE), DT_C) < 0.075:
        continue   # downtown is meant to be a tight grid
    g = _g[i]
    close = 0
    for t in np.linspace(0.15, 0.85, 8) * g.length:
        q = g.interpolate(t)
        dq = _dir_at(g, t)
        for j in _tree.query(q.buffer(PARALLEL_MIN_M)):
            if j == i or j in _dropped or out_roads[j]["tier"] not in ("res", "svc", "art", "fwy"):
                continue
            h = _g[j]
            if h.distance(q) > PARALLEL_MIN_M:
                continue
            dh = _dir_at(h, h.project(q))
            if abs(dq[0] * dh[0] + dq[1] * dh[1]) > 0.94:
                close += 1
                break
    if close >= 5:
        _dropped.add(i)
out_roads = [r for k, r in enumerate(out_roads) if k not in _dropped]
print("dropped side-by-side streets:", len(_dropped))

# final guard: any local street end that touches nothing is either dropped (short stub)
# or becomes a deliberate cul-de-sac (long street) -- never a street ending in mid-air
from shapely.strtree import STRtree
_de = [[round(x * SIZE, 1), round(y * SIZE, 1)] for x, y in dead_ends]

# junction spacing: no clusters of intersections. A street end that lands within
# JUNCTION_MIN_M of another junction is merged into it (or cut back to its own
# nearby crossing); dead-end stubs that start next to a junction are removed.
from shapely.ops import substring
JUNCTION_MIN_M = 30.0
_g = [LineString(r["pts"]) for r in out_roads]
_tree = STRtree(_g)
_JT = ("res", "svc", "art", "path")          # alleys/ramps/freeways never count as junctions
_nodes = []
for i, g in enumerate(_g):
    if out_roads[i]["tier"] not in _JT:
        continue
    for j in _tree.query(g.buffer(1.0)):
        if j <= i or out_roads[j]["tier"] not in _JT:
            continue
        x = g.intersection(_g[j])
        for h in getattr(x, "geoms", [x]):
            if not x.is_empty and h.geom_type == "Point":
                _nodes.append((h.x, h.y, i, j))
_node_tree = STRtree([Point(n[0], n[1]) for n in _nodes])
_de_set = {tuple(d) for d in _de}
_drop = set()
for i, r in enumerate(out_roads):
    if r["tier"] not in ("res", "svc", "path") or r["pts"][0] == r["pts"][-1]:
        continue
    _mid = _g[i].interpolate(0.5, normalized=True)
    if math.dist((_mid.x / SIZE, _mid.y / SIZE), DT_C) < 0.08:
        continue   # downtown's tight grid is meant to have close junctions
    pts = r["pts"]
    if len(pts) == 2 and (tuple(pts[0]) in _de_set or tuple(pts[1]) in _de_set):
        base = pts[1] if tuple(pts[0]) in _de_set else pts[0]
        if any(1.0 < math.dist(base, _nodes[k][:2]) < JUNCTION_MIN_M for k in _node_tree.query(Point(base).buffer(JUNCTION_MIN_M))):
            _drop.add(i)
            _de_set.discard(tuple(pts[0]))
            _de_set.discard(tuple(pts[1]))
        continue
    for end_idx in (0, -1):
        e = pts[end_idx]
        hosts = [j for j in _tree.query(Point(e).buffer(12)) if j != i and out_roads[j]["tier"] in _JT and _g[j].distance(Point(e)) < 12]
        if not hosts:
            continue
        cands = [k for k in _node_tree.query(Point(e).buffer(JUNCTION_MIN_M))
                 if 1.0 < math.dist(e, _nodes[k][:2]) < JUNCTION_MIN_M and i not in _nodes[k][2:] and (_nodes[k][2] in hosts or _nodes[k][3] in hosts)]
        if cands:   # another junction on the same road right next to ours: meet there instead
            k = min(cands, key=lambda c: math.dist(e, _nodes[c][:2]))
            pts[end_idx] = [round(_nodes[k][0], 1), round(_nodes[k][1], 1)]
    r["pts"] = pts
out_roads = [r for k, r in enumerate(out_roads) if k not in _drop]
_de = [list(d) for d in _de_set]
print("junction cleanup: dropped", len(_drop))
for _ in range(3):
    geoms = [LineString(r["pts"]) for r in out_roads]
    tree = STRtree(geoms)
    keep, changed = [], False
    for i, r in enumerate(out_roads):
        if r["tier"] in ("fwy", "ramp", "trail") or r["pts"][0] == r["pts"][-1]:
            keep.append(r)
            continue
        loose = []
        for e in (r["pts"][0], r["pts"][-1]):
            pt = Point(e)
            if min(e[0], e[1], SIZE - e[0], SIZE - e[1]) < 12 or any(math.dist(e, d) < 12 for d in _de):
                continue
            near = [j for j in tree.query(pt.buffer(12)) if j != i and geoms[j].distance(pt) < 12]
            if not near:
                loose.append(e)
        if loose and geoms[i].length < 245:
            changed = True
            continue
        for e in loose:
            _de.append(e)
        keep.append(r)
    out_roads = keep
    if not changed:
        break
areas = [("hills", HILLS), ("mountains", MTN), ("park", PARK), ("park", BASIN), ("airfield", AIRFIELD),
         ("foothill", ROT), ("industrial", IND), ("downtown", DT_BLOB)]
data = {
    "format": "ganstoid.city", "version": 1, "id": "base:city", "size_m": SIZE,
    "roads": out_roads,
    "areas": [{"id": "base:area_%02d" % i, "kind": k, "poly": exp_poly(p)} for i, (k, p) in enumerate(areas)],
    "river": ex(list(RIVER.coords)),
    "rail": [ex(list(RIVER.offset_curve(-0.022 - 0.004 * k).coords)) for k in range(6)],
    "dead_ends": _de,
    "dark_spots": [[round(x * SIZE, 1), round(y * SIZE, 1)] for x, y in spots],
    "spawn": [round(0.20 * SIZE, 1), round(0.30 * SIZE, 1)],
}
os.makedirs("/home/claude/ganstoid/data/city", exist_ok=True)
with open("/home/claude/ganstoid/data/city/city_v1.json", "w") as f:
    json.dump(data, f, separators=(",", ":"))
print("exported", len(out_roads), "roads", os.path.getsize("/home/claude/ganstoid/data/city/city_v1.json") // 1024, "KB")
