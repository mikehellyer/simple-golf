#!/usr/bin/env python3
"""Turn a golf course mapped in OpenStreetMap into a Simple-Golf course file.

OpenStreetMap golf mapping gives each hole as a line (golf=hole, with ref and
par) from tee to green, plus shapes for greens, tees, fairways, bunkers, water
and woods. This tool keeps, for each hole, the shapes near it, turns them so
the hole plays from the origin straight up the +Z axis (as the game's holes
do), fills in a fairway where none is mapped, and writes everything to a JSON
course file in courses/.

Usage (needs nothing beyond Python's standard library):

  tools/import_osm_course.py --bbox 30.186,-81.402,30.206,-81.383 \\
      --holes "Stadium" --name "Ponte Vedra Stadium" \\
      --description "Based on the Stadium Course at Sawgrass" \\
      --out courses/ponte-vedra-stadium.json

  --bbox south,west,north,east downloads the area from the OpenStreetMap API;
  --osm FILE uses a saved .osm file instead. --holes picks the holes whose
  name starts with that text (for venues with several courses).

The output is a derived database of OpenStreetMap data, so it is licensed
under the ODbL and must credit "© OpenStreetMap contributors".
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.request
import xml.etree.ElementTree as ET

EARTH = 6371000.0
NEAR_HOLE = 90.0       # shapes within this distance of a hole's line are kept
FAIRWAY_HALF = 15.0    # half-width of a filled-in fairway, metres
FAIRWAY_START = 0.30   # filled-in fairways start this far along the hole


def download(bbox: str) -> bytes:
    s, w, n, e = bbox.split(",")
    url = f"https://api.openstreetmap.org/api/0.6/map?bbox={w},{s},{e},{n}"
    req = urllib.request.Request(url, headers={"User-Agent": "simple-golf-course-import"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def join_rings(segments):
    """Join way segments (lists of node ids) into closed rings, the way
    multipolygon outlines are drawn in pieces. Unclosable pieces are dropped."""
    segments = [list(s) for s in segments if len(s) >= 2]
    rings = []
    while segments:
        ring = segments.pop(0)
        while ring[0] != ring[-1]:
            for i, s in enumerate(segments):
                if s[0] == ring[-1]:
                    ring += s[1:]
                elif s[-1] == ring[-1]:
                    ring += s[::-1][1:]
                elif s[-1] == ring[0]:
                    ring = s[:-1] + ring
                elif s[0] == ring[0]:
                    ring = s[::-1][:-1] + ring
                else:
                    continue
                segments.pop(i)
                break
            else:
                break
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring)
    return rings


def parse(xml: bytes):
    root = ET.fromstring(xml)
    nodes = {n.get("id"): (float(n.get("lat")), float(n.get("lon"))) for n in root.iter("node")}
    ways = {}
    for w in root.iter("way"):
        tags = {t.get("k"): t.get("v") for t in w.iter("tag")}
        ids = [nd.get("ref") for nd in w.iter("nd") if nd.get("ref") in nodes]
        ways[w.get("id")] = (tags, ids)

    def coords(ids):
        return [nodes[i] for i in ids]

    features = []  # (kind, [latlon...]); kind "island" = a hole cut out of water
    for wid, (tags, ids) in ways.items():
        kind = classify(tags)
        # Only closed ways are areas; an open way tagged as water is a stream or shore line.
        if kind and len(ids) >= 4 and ids[0] == ids[-1]:
            features.append((kind, coords(ids)))
    # Lakes and woods are often multipolygon relations: their outlines are
    # split across several ways, and islands are cut out as inner rings.
    for rel in root.iter("relation"):
        tags = {t.get("k"): t.get("v") for t in rel.iter("tag")}
        kind = classify(tags)
        if not kind or tags.get("type") != "multipolygon":
            continue
        outer, inner = [], []
        for m in rel.iter("member"):
            if m.get("type") == "way" and m.get("ref") in ways:
                (inner if m.get("role") == "inner" else outer).append(ways[m.get("ref")][1])
        for ring in join_rings(outer):
            features.append((kind, coords(ring)))
        if kind == "water":
            for ring in join_rings(inner):
                features.append(("island", coords(ring)))
    holes = []
    for wid, (tags, ids) in ways.items():
        if tags.get("golf") == "hole" and len(ids) >= 2:
            holes.append((tags, coords(ids)))
    return holes, features


def classify(tags: dict) -> str | None:
    golf = tags.get("golf")
    if golf in ("green", "tee", "fairway", "bunker"):
        return golf
    if golf in ("water_hazard", "lateral_water_hazard") or tags.get("natural") == "water" or "water" in tags:
        return "water"
    if tags.get("natural") in ("wood", "scrub") or tags.get("landuse") == "forest":
        return "woods"
    return None


class Frame:
    """Local metres around a reference point (x east, y north)."""

    def __init__(self, lat0: float, lon0: float):
        self.lat0, self.lon0 = lat0, lon0
        self.k = math.cos(math.radians(lat0))

    def xy(self, p):
        return ((p[1] - self.lon0) * math.pi / 180 * EARTH * self.k, (p[0] - self.lat0) * math.pi / 180 * EARTH)


def seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def line_dist(p, line):
    return min(seg_dist(p, line[i], line[i + 1]) for i in range(len(line) - 1))


def centroid(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def inside(p, poly) -> bool:
    x, y = p
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def polyline_length(line):
    return sum(math.hypot(line[i + 1][0] - line[i][0], line[i + 1][1] - line[i][1]) for i in range(len(line) - 1))


def point_along(line, distance):
    for i in range(len(line) - 1):
        a, b = line[i], line[i + 1]
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        if distance <= seg or i == len(line) - 2:
            t = 0.0 if seg == 0 else min(distance / seg, 1.0)
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), (b[0] - a[0], b[1] - a[1])
        distance -= seg
    return line[-1], (0.0, 1.0)


def fairway_corridor(line, start_frac, end_point):
    """A fairway shape along the hole's line, from start_frac of the way to the
    green's front edge, FAIRWAY_HALF wide on each side."""
    total = polyline_length(line)
    end = total - 0.0
    left, right = [], []
    d = total * start_frac
    while d <= end:
        (x, y), (dx, dy) = point_along(line, d)
        n = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / n, dx / n
        left.append((x + nx * FAIRWAY_HALF, y + ny * FAIRWAY_HALF))
        right.append((x - nx * FAIRWAY_HALF, y - ny * FAIRWAY_HALF))
        d += 10.0
    return left + right[::-1]


def build(holes_osm, features, prefix: str):
    chosen = []
    for tags, pts in holes_osm:
        name = tags.get("name", "")
        ref = (tags.get("ref") or "").split(";")[0]
        if prefix and not name.lower().startswith(prefix.lower()):
            continue
        if not ref.isdigit():
            continue
        chosen.append((int(ref), tags, pts))
    chosen.sort(key=lambda h: h[0])
    if not chosen:
        sys.exit("No holes found; check --holes against the hole names in the data.")
    all_pts = [p for _, _, pts in chosen for p in pts]
    frame = Frame(sum(p[0] for p in all_pts) / len(all_pts), sum(p[1] for p in all_pts) / len(all_pts))
    shapes = [(kind, [frame.xy(p) for p in pts]) for kind, pts in features]
    greens = [poly for kind, poly in shapes if kind == "green"]

    out = []
    for number, tags, pts in chosen:
        line = [frame.xy(p) for p in pts]
        # Holes should run tee → green; flip any drawn the other way.
        def green_gap(p):
            return min((math.dist(p, centroid(g)) for g in greens), default=1e9)
        if green_gap(line[0]) < green_gap(line[-1]):
            line.reverse()
        own_green = min(greens, key=lambda g: math.dist(line[-1], centroid(g)))
        # Rotate so the tee is at the origin and the green straight up +Z.
        tx, ty = line[0]
        gx, gy = centroid(own_green)
        angle = math.atan2(gx - tx, gy - ty)
        c, s = math.cos(angle), math.sin(angle)

        def local(p):
            x, y = p[0] - tx, p[1] - ty
            # The game's x axis points to the golfer's left when facing +Z,
            # which is the mirror image of map east; flip x to keep the
            # course the right way round.
            return (-(x * c - y * s), x * s + y * c)

        near = [(kind, poly) for kind, poly in shapes
                if any(line_dist(p, line) < NEAR_HOLE for p in poly[::max(1, len(poly) // 12)] + [centroid(poly)])]
        hole = {"number": number, "par": int(tags.get("par", 4)),
                "line": [round(v, 1) for p in line for v in local(p)],
                "green": [round(v, 1) for p in own_green for v in local(p)],
                "greens": [], "tees": [], "fairways": [], "bunkers": [], "water": [], "islands": [], "woods": []}
        for kind, poly in near:
            if poly is own_green:
                continue
            hole[kind + "s" if kind in ("green", "tee", "fairway", "bunker", "island") else kind].append(
                [round(v, 1) for p in poly for v in local(p)])
        # Fill in a fairway only where the mapped ones barely cover the
        # hole's line (some courses don't map fairways at all).
        total = polyline_length(line)
        samples = [point_along(line, total * i / 20)[0] for i in range(6, 19)]
        fairway_polys = [poly for kind, poly in near if kind == "fairway"]
        covered = sum(1 for p in samples if any(inside(p, f) for f in fairway_polys)) / len(samples)
        if hole["par"] >= 4 and covered < 0.35:
            hole["fairways"].append([round(v, 1) for p in fairway_corridor(line, FAIRWAY_START, None) for v in local(p)])
            hole["fairway_filled_in"] = True
        out.append(hole)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--bbox", help="south,west,north,east")
    src.add_argument("--osm", help="a saved .osm file")
    ap.add_argument("--holes", default="", help="only holes whose name starts with this")
    ap.add_argument("--name", required=True)
    ap.add_argument("--description", default="")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    xml = download(args.bbox) if args.bbox else open(args.osm, "rb").read()
    holes_osm, features = parse(xml)
    holes = build(holes_osm, features, args.holes)
    course = {
        "format": 1,
        "name": args.name,
        "description": args.description,
        "attribution": "Course layout © OpenStreetMap contributors, available under the Open Database Licence (ODbL)",
        "licence": "ODbL-1.0",
        "source": "https://www.openstreetmap.org" + (f" (bbox {args.bbox})" if args.bbox else ""),
        "holes": holes,
    }
    with open(args.out, "w") as f:
        json.dump(course, f, separators=(",", ":"))
    par = sum(h["par"] for h in holes)
    filled = sum(1 for h in holes if h.get("fairway_filled_in"))
    print(f"Wrote {args.out}: {len(holes)} holes, par {par}, {filled} fairways filled in")


if __name__ == "__main__":
    main()
