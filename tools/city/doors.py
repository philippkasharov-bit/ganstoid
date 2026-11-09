"""MG1a: give every building a front door: the point just outside its footprint
that faces the nearest street (boulevard or local street). Sim entities stand at
doors, so NPCs can walk to/from any building. Adds "door": [x, y] in place.
Run after join_buildings.py.
Usage: python3 -I doors.py <city_v1.json> <buildings_v1.json>
"""
import json
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points
from shapely.strtree import STRtree

STEP_OUT_M = 1.2   # door sits this far outside the wall, toward the street


def main(city_path, bld_path):
    city = json.load(open(city_path))
    raw = json.load(open(bld_path))
    streets = [LineString(r["pts"]) for r in city["roads"] if r["tier"] in ("art", "res")]
    tree = STRtree(streets)
    footprints = [Polygon(b["poly"]).buffer(0) for b in raw["buildings"]]
    walls = STRtree(footprints)
    moved = 0
    for i, b in enumerate(raw["buildings"]):
        poly = Polygon(b["poly"]).buffer(0)
        if poly.geom_type != "Polygon":   # self-touching footprint: use its largest part
            poly = max(poly.geoms, key=lambda g: g.area)
        road = streets[tree.nearest(poly)]
        on_wall, on_road = nearest_points(poly.exterior, road)
        dx, dy = on_road.x - on_wall.x, on_road.y - on_wall.y
        d = (dx * dx + dy * dy) ** 0.5 or 1.0
        step = min(STEP_OUT_M, d)
        door = Point(on_wall.x + dx / d * step, on_wall.y + dy / d * step)
        if blocked(door, walls, footprints):
            door = free_side(poly, road, walls, footprints) or door
            moved += 1
        b["door"] = [round(door.x, 1), round(door.y, 1)]
    json.dump(raw, open(bld_path, "w"), separators=(",", ":"))
    print("doors added to %d buildings (%d moved off a neighbour's wall)" % (len(raw["buildings"]), moved))


def blocked(p, walls, footprints):
    return any(footprints[k].distance(p) < 0.3 for k in walls.query(p.buffer(0.3)))


def free_side(poly, road, walls, footprints):
    """Door facing the street was inside a neighbour: try every 2 m of wall, stepping
    outward, and keep the free spot closest to the street."""
    ring, c, best = poly.exterior, poly.centroid, None
    for k in range(int(ring.length // 2.0) + 1):
        w = ring.interpolate(k * 2.0)
        dx, dy = w.x - c.x, w.y - c.y
        d = (dx * dx + dy * dy) ** 0.5 or 1.0
        cand = Point(w.x + dx / d * STEP_OUT_M, w.y + dy / d * STEP_OUT_M)
        if poly.distance(cand) < 0.3 or blocked(cand, walls, footprints):
            continue
        if best is None or road.distance(cand) < road.distance(best):
            best = cand
    return best


if __name__ == "__main__":
    main(*sys.argv[1:3])
