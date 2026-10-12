#!/usr/bin/env python3
"""Deterministic offline audit of travel geometry and straight walking coverage.

Run from anywhere: python3 tools/validate_terrain_geometry.py
Needs the existing tools/.cache/travel CSV/TSV extracts and Lua 5.1 (the
addon's toolchain). Supply --lua /path/to/lua if lua5.1 is not on PATH.
No downloads or writes.
--strict-suspects also fails unverified coverage findings; default fails only
data invariants and runtime regressions. --details prints every suspect example.

This is NOT a collision/navmesh oracle: UiMapAssignment supplies rectangles,
not physical zone boundaries. Region transit and long chords are review leads,
never declarations that a particular piece of terrain is impassable.
"""
import argparse
import csv
import itertools
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "WaypointTracker/TravelData.lua"


def lua_rows(text, key):
    match = re.search(r"\b" + key + r"\s*=\s*\[\[\n(.*?)\n\]\]", text, re.S)
    if not match:
        raise ValueError(f"{DATA}: missing TSV block {key}")
    first = text[:match.start(1)].count("\n") + 1
    return [(first + i, line.split("\t")) for i, line in enumerate(match[1].splitlines()) if line]


def read_csv(path):
    with path.open(encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def indoor_node_area(n, surface, areas, indoor, source_nodes, source_indoor):
    """Resolve an anchor override only with independent Mapzeroth provenance.

    This is node context, not room geometry. Ordinary positions must still
    agree with AreaAt's surface classification. Never exempt all indoor areas.
    """
    raw = source_nodes.get(n["id"])
    source_area = raw[2] if raw else None
    if source_area in source_indoor and areas.get(n["area"]) != source_area:
        return surface, "declared routing area differs from Mapzeroth's indoor container"
    flag = n.get("override", "")
    if not flag:
        return surface, None
    if flag != "mapzeroth-indoor":
        return surface, "unknown area provenance flag"
    if not raw or source_area not in source_indoor or n["area"] not in indoor:
        return surface, "override requires a source node and source/shipped indoor markers"
    # Match the generator's serialized map precision, without a spatial radius.
    if (n["kind"] != raw[1] or n["m"] != int(raw[3])
            or n["x"] != round(float(raw[4]) * 100, 2) / 100
            or n["y"] != round(float(raw[5]) * 100, 2) / 100):
        return surface, "override anchor differs from its captured Mapzeroth node"
    if surface == n["area"]:
        return surface, "redundant indoor override: surface already represents this area"
    return n["area"], None


def world(a, x, y):
    return a["cont"], a["top"] - y * a["h"], a["left"] - x * a["w"]


def project(a, p):
    if a["cont"] != p[0]:
        return None
    return (a["left"] - p[2]) / a["w"], (a["top"] - p[1]) / a["h"]


def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def intersects(p, q, r, s):
    """Independent parametric intersection oracle (including endpoint contact)."""
    if p[0] != q[0] or p[0] != r[0] or p[0] != s[0]:
        return False
    if p == q:
        return False  # staying still is allowed by the planner
    a = (q[1] - p[1], q[2] - p[2])
    b = (s[1] - r[1], s[2] - r[2])
    c = (r[1] - p[1], r[2] - p[2])
    den = cross(a, b)
    if abs(den) > 1e-7:
        t, u = cross(c, b) / den, cross(c, a) / den
        return -1e-10 <= t <= 1+1e-10 and -1e-10 <= u <= 1+1e-10
    if abs(cross(c, a)) > 1e-7:
        return False
    axis = 1 if abs(a[0]) >= abs(a[1]) else 2
    return max(min(p[axis], q[axis]), min(r[axis], s[axis])) <= min(max(p[axis], q[axis]), max(r[axis], s[axis]))


def circle_span(p, q, region):
    """Open interval where a projected straight segment lies inside a circle."""
    vx, vy = q[0] - p[0], q[1] - p[1]
    dx, dy = p[0] - region["x"], p[1] - region["y"]
    aa = vx * vx + vy * vy
    if aa == 0:
        return None
    bb = 2 * (vx * dx + vy * dy)
    cc = dx * dx + dy * dy - region["r"] ** 2
    disc = bb * bb - 4 * aa * cc
    if disc <= 0:
        return None
    lo = max(0, (-bb - math.sqrt(disc)) / (2 * aa))
    hi = min(1, (-bb + math.sqrt(disc)) / (2 * aa))
    return (lo, hi) if lo < hi else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / "tools/fixtures/travel")
    parser.add_argument("--lua", default=shutil.which("lua5.1"))
    parser.add_argument("--strict-suspects", action="store_true")
    parser.add_argument("--details", action="store_true")
    args = parser.parse_args()
    text = DATA.read_text(encoding="utf-8")
    area_match = re.search(r"\bareas\s*=\s*\{(.*?)\}", text, re.S)
    areas = {i + 1: a for i, a in enumerate(re.findall(r'"([^"]+)"', area_match[1]))}
    indoor_match = re.search(r"\bindoor\s*=\s*\{(.*?)\}", text, re.S)
    indoor = {int(a) for a in re.findall(r"\[(\d+)\]\s*=\s*true", indoor_match[1])}
    # These checksummed fixtures are independent of generated override flags.
    source_nodes = {}
    with (args.cache / "mz_nodes.tsv").open(encoding="utf-8") as stream:
        for line in stream:
            if line.strip() and not line.startswith("#"):
                f = line.rstrip("\n").split("\t")
                source_nodes[f[0]] = f
    source_indoor = set()
    with (args.cache / "mz_misc.tsv").open(encoding="utf-8") as stream:
        for line in stream:
            f = line.rstrip("\n").split("\t")
            if len(f) > 2 and f[0] == "container" and f[2] == "indoor":
                source_indoor.add(f[1])
    ui = {int(r["ID"]): r for r in read_csv(args.cache / "UiMap.csv")}
    assignments, assignment_counts = {}, Counter()
    for r in read_csv(args.cache / "UiMapAssignment.csv"):
        if [float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")] != [0, 0, 1, 1]:
            continue
        m = int(r["UiMapID"])
        assignment_counts[m] += 1
        # First full assignment matches generator policy, not smallest rectangle.
        if m not in assignments:
            assignments[m] = dict(cont=int(r["MapID"]), top=float(r["Region_3"]),
                left=float(r["Region_4"]), h=float(r["Region_3"]) - float(r["Region_0"]),
                w=float(r["Region_4"]) - float(r["Region_1"]), id=r["ID"])
    maps = {int(f[0]): int(f[1]) for _, f in lua_rows(text, "maps")}
    cities = {int(f[0]) for _, f in lua_rows(text, "cities")}
    regions = []
    for line, f in lua_rows(text, "regions"):
        regions.append(dict(m=int(f[0]), area=int(f[1]), x=float(f[2]) / 100,
                            y=float(f[3]) / 100, r=float(f[4]) / 100, line=line))
    def area_at(m, x, y):
        # Real AreaAt gives regions priority, then the map, then parent projection.
        for _ in range(6):
            for r in regions:
                if r["m"] == m and math.hypot(x - r["x"], y - r["y"]) <= r["r"]:
                    return r["area"]
            if m in maps:
                return maps[m]
            parent = int(ui.get(m, {}).get("ParentUiMapID", 0))
            if not parent or m not in assignments or parent not in assignments:
                return None
            point = project(assignments[parent], world(assignments[m], x, y))
            if point is None:
                return None
            m, (x, y) = parent, point
        return None
    errors, suspects, runtime_input = [], [], []
    def error(code, line, entry, value, reason):
        errors.append(f"FAIL {code} WaypointTracker/TravelData.lua:{line} entry={entry} value={value}: {reason}")
    for m, a in sorted(assignments.items()):
        if not all(math.isfinite(a[k]) for k in ("top", "left", "h", "w")) or a["h"] <= 0 or a["w"] <= 0:
            raise ValueError(f"UiMapAssignment ID={a['id']} map={m}: invalid rectangle {a}")
        info = ui.get(m, {})
        runtime_input.append("\t".join(map(str, ["M", m, a["cont"], a["top"], a["left"], a["h"], a["w"],
            info.get("ParentUiMapID", 0), info.get("Type", 3)])))
        for x, y in [(0, 0), (.5, .5), (1, 1), (.23, .81)]:
            runtime_input.append("\t".join(map(str, ["G", m, x, y, *world(a, x, y)])))
    nodes = {}
    taxi = {int(r["ID"]): r for r in read_csv(args.cache / "TaxiNodes.csv")}
    for line, f in lua_rows(text, "nodes"):
        n = dict(id=f[0], kind=f[1], area=int(f[2]), p=(int(f[3]), float(f[4]), float(f[5])),
                 m=int(f[6]), x=float(f[7]) / 100, y=float(f[8]) / 100, city=f[9], line=line,
                 override=f[14] if len(f) > 14 else "")
        if n["id"] in nodes:
            error("DUPLICATE_NODE", line, n["id"], n["id"], "IDs must be unique")
        nodes[n["id"]] = n
        a = assignments.get(n["m"])
        if not a:
            error("NO_TRANSFORM", line, n["id"], n["m"], "no cached full client assignment")
            continue
        exact = world(a, n["x"], n["y"])
        # Map % is rounded to .01; world to .1 yards. Account for BOTH.
        tolerance = math.hypot(a["w"], a["h"]) * .00005 + math.sqrt(2) * .05 + 1e-6
        distance = math.hypot(exact[1] - n["p"][1], exact[2] - n["p"][2])
        if exact[0] != n["p"][0] or distance > tolerance:
            error("WORLD_TRANSFORM", line, n["id"], n["p"], f"client assignment {a['id']} gives {exact}; delta={distance:.3f} yd tolerance={tolerance:.3f}")
        n["p"] = exact  # runtime prefers the map transform over serialized fallback
        if n["kind"] == "taxi" and n["id"].startswith("TAXI_"):
            raw = taxi.get(int(n["id"][5:]))
            if raw:
                td = math.hypot(float(raw["Pos_0"]) - exact[1], float(raw["Pos_1"]) - exact[2])
                if int(raw["ContinentID"]) != exact[0] or td > tolerance:
                    error("TAXI_POSITION", line, n["id"], exact, f"TaxiNodes ID={raw['ID']} authoritative position mismatch ({td:.3f} yd)")
        physical = area_at(n["m"], n["x"], n["y"])
        resolved, reason = indoor_node_area(n, physical, areas, indoor, source_nodes, source_indoor)
        if reason:
            error("INDOOR_PROVENANCE", line, n["id"], n["override"], reason)
        if resolved != n["area"]:
            error("ANCHOR_AREA", line, n["id"], areas.get(n["area"], n["area"]),
                  f"AreaAt(map={n['m']},x={n['x']*100:.2f},y={n['y']*100:.2f})={areas.get(physical, physical)}; graph walking group differs from physical position")
        runtime_input.append("\t".join(map(str, ["A", n["m"], n["x"], n["y"], physical, f"WaypointTracker/TravelData.lua:{line} {n['id']} surface"])))
        runtime_input.append("\t".join(map(str, ["N", n["m"], n["x"], n["y"], n["area"], n["id"]])))
    links = lua_rows(text, "links")
    for line, f in links:
        if f[0] not in nodes or f[1] not in nodes:
            error("DANGLING_LINK", line, f[0] + ">" + f[1], f[:3], "missing endpoint")
            continue
        a, b = nodes[f[0]], nodes[f[1]]
        if f[2] in ("walk", "lift") and a["p"][0] != b["p"][0]:
            error("CROSS_CONTINENT_WALK", line, f[0] + ">" + f[1], f[2], "walking cannot join different world instances")
    barriers = []
    for line, f in lua_rows(text, "barriers"):
        m = int(f[0]); a = assignments[m]
        p = world(a, float(f[1]) / 100, float(f[2]) / 100)
        q = world(a, float(f[3]) / 100, float(f[4]) / 100)
        rawp = (int(f[5]), float(f[6]), float(f[7]))
        rawq = (int(f[5]), float(f[8]), float(f[9]))
        if p == q:
            error("DEGENERATE_BARRIER", line, f"map {m}", f[:5], "zero length")
        for exact, raw in [(p, rawp), (q, rawq)]:
            if exact[0] != raw[0] or math.hypot(exact[1] - raw[1], exact[2] - raw[2]) > .071:
                error("BARRIER_TRANSFORM", line, f"map {m}", raw, f"client transform gives {exact}")
        barriers.append((line, m, p, q))
    # Exact terrain verdicts supplement the original separator oracle. The
    # model below is independent of the Lua predicate and tests both cloned
    # endpoint coordinates and substantial partial overlaps of blocked chords.
    blocked_chords = []
    for _, f in lua_rows(text, "walkEvidence"):
        if f[2] == "TERRAIN_BLOCKED":
            endpoints = []
            for offset in (8, 14):
                endpoints.append(world(assignments[int(f[offset+3])], float(f[offset+4])/100, float(f[offset+5])/100))
            blocked_chords.append(endpoints)
    def terrain_blocked(p, q):
        for a,b in blocked_chords:
            if p[0] != a[0] or q[0] != a[0]: continue
            dx,dy = b[1]-a[1],b[2]-a[2]
            length2 = dx*dx+dy*dy
            if not length2: continue
            # Fast rejection before projecting densely generated grid probes.
            if not all(min(a[k],b[k])-3 <= point[k] <= max(a[k],b[k])+3 for point in (p,q) for k in (1,2)): continue
            def project_point(point):
                t = max(0,min(1,((point[1]-a[1])*dx+(point[2]-a[2])*dy)/length2))
                return t,(point[1]-a[1]-t*dx)**2+(point[2]-a[2]-t*dy)**2
            tp,dp = project_point(p);tq,dq = project_point(q)
            if dp <= 9 and dq <= 9 and abs(tp-tq)*math.sqrt(length2) > 30: return True
        return False
    def allowed(p, q):
        return p[0] == q[0] and not terrain_blocked(p,q) and not any(intersects(p, q, r, s) for _, _, r, s in barriers)
    def probe(p, q, label):
        expected = int(allowed(p, q))
        runtime_input.append("\t".join(map(str, ["P", *p, *q, expected, label])))
        return expected
    counts = Counter()
    per_map = defaultdict(Counter)
    longest = {}
    # Independent verdict-backed witnesses survive deletion of a generated row.
    witnesses = [
        (1424, (.556, .346), (.38, .36), 1, "road bend south of Darrow Hill"),
    ]
    for m, start, end, expected, label in witnesses:
        p, q = world(assignments[m], *start), world(assignments[m], *end)
        runtime_input.append("\t".join(map(str, ["P", *p, *q, expected, f"tools/travel_extra.tsv map={m} {label}"])))
        counts["fixed_terrain_witnesses"] += 1
    policy = json.loads((ROOT/'tools/fixtures/travel/verified-routing.json').read_text())
    for r in policy['barriers']:
        p, q = (r['cont'], *r['a']), (r['cont'], *r['b'])
        runtime_input.append('\t'.join(map(str, ['P', *p, *q, 0, r['id'] + ' terrain-BLOCKED crossing'])))
        counts['fixed_terrain_witnesses'] += 1
    # Touches, collinearity, endpoint reversal, staying still and different
    # continents are rarely exercised by an ordinary grid.
    for line, m, p, q in barriers:
        dx, dy = q[1] - p[1], q[2] - p[2]
        length = math.hypot(dx, dy)
        nx, ny = -dy / length * 25, dx / length * 25
        mid = (p[0], (p[1] + q[1]) / 2, (p[2] + q[2]) / 2)
        cases = [(p, q), (q, p), (p, p), (mid, mid),
                 ((mid[0], mid[1] + nx, mid[2] + ny), (mid[0], mid[1] - nx, mid[2] - ny)),
                 ((p[0], p[1] + nx, p[2] + ny), (q[0], q[1] + nx, q[2] + ny)),
                 (p, (1 - p[0], q[1], q[2]))]
        for i, (start, end) in enumerate(cases):
            probe(start, end, f"WaypointTracker/TravelData.lua:{line} barrier edge case {i}")
            counts["barrier_edge_cases"] += 1
    # All same-area pairs, across different/overlapping maps as well as one map.
    for a, b in itertools.combinations(sorted(nodes.values(), key=lambda n: n["id"]), 2):
        if a["id"].startswith("TERRAIN_") or b["id"].startswith("TERRAIN_"):
            continue # indexed adjacent corridors cannot infer all-to-all edges
        if a["area"] != b["area"] or a["city"] != b["city"]:
            continue
        counts["graph_pairs"] += 1
        ok = probe(a["p"], b["p"], f"{a['id']} -> {b['id']}")
        counts["blocked_graph_pairs"] += not ok
        if ok and a["p"][0] == b["p"][0]:
            distance = math.hypot(a["p"][1] - b["p"][1], a["p"][2] - b["p"][2])
            if distance >= 1500:
                per_map[a["m"]]["long_graph"] += 1
                key = a["m"]
                if key not in longest or distance > longest[key][0]:
                    longest[key] = distance, a, b
    for m, (distance, a, b) in sorted(longest.items()):
        suspects.append(f"SUSPECT LONG_INFERRED WaypointTracker/TravelData.lua:{a['line']} map={m} entry={a['id']}>{b['id']} distance={distance:.1f} yd area={areas[a['area']]}: no intersecting mapped barrier; {per_map[m]['long_graph']} long allowed chords in this map need terrain/road connectivity evidence")
    # Dense fixed grids in EVERY travel map. Not a walkability ground truth.
    # Endpoints stay in one routing area; inspect their entire chord analytically.
    samples = [i / 10 for i in range(1, 10)]
    transit_examples, transit_counts = {}, Counter()
    for m in sorted(maps):
        if m not in assignments:
            continue
        a = assignments[m]
        points = [(x, y, area_at(m, x, y), world(a, x, y)) for x in samples for y in samples]
        relevant = [r for r in regions if r["m"] == m]
        for p, q in itertools.combinations(points, 2):
            if p[2] != q[2]:
                continue
            counts["grid_pairs"] += 1
            ok = probe(p[3], q[3], f"map={m} grid=({p[0]:.1f},{p[1]:.1f})->({q[0]:.1f},{q[1]:.1f})")
            counts["blocked_grid_pairs"] += not ok
            if not ok:
                continue
            for r in relevant:
                if r["area"] == p[2]:
                    continue
                span = circle_span(p[:2], q[:2], r)
                if not span:
                    continue
                # Ignore a circle hidden by an earlier overlapping region.
                mid = sum(span) / 2
                mx, my = p[0] + mid * (q[0] - p[0]), p[1] + mid * (q[1] - p[1])
                if area_at(m, mx, my) == p[2]:
                    continue
                # Circles are estimates; report topology mismatch as SUSPECT.
                key = (m, r["area"])
                transit_counts[key] += 1
                transit_examples.setdefault(key, (p, q, r))
                per_map[m]["region_transit"] += 1
    for (m, ar), amount in sorted(transit_counts.items()):
        p, q, r = transit_examples[m, ar]
        suspects.append(f"SUSPECT REGION_TRANSIT WaypointTracker/TravelData.lua:{r['line']} map={m} area={areas[ar]} count={amount}: inferred chord ({p[0]*100:.0f},{p[1]*100:.0f})->({q[0]*100:.0f},{q[1]*100:.0f}) enters another routing area without its registered access; survey circle boundary and chord")
    # Cross-map overlap checks: evaluate only real anchors, never infer zone
    # ownership from rectangle area. Disagreement here is a lead, not an error.
    overlaps = defaultdict(list)
    for n in sorted(nodes.values(), key=lambda n: n["id"]):
        if n["kind"] != "taxi" or n["m"] in cities:
            continue
        for m in sorted(maps):
            if m == n["m"] or m in cities or m not in assignments:
                continue
            xy = project(assignments[m], n["p"])
            if xy and all(0 <= v <= 1 for v in xy):
                runtime_input.append("\t".join(map(str, ["O", n["m"], n["x"], n["y"], m, *xy])))
                ar = area_at(m, *xy)
                counts["overlap_anchor_projections"] += 1
                if ar != n["area"]:
                    overlaps[(n["m"], m)].append((n, xy, ar))
    for key, values in sorted(overlaps.items()):
        n, xy, ar = values[0]
        suspects.append(f"SUSPECT OVERLAP_AREA WaypointTracker/TravelData.lua:{n['line']} maps={key} count={len(values)} example={n['id']} projected=({xy[0]*100:.2f},{xy[1]*100:.2f}) graph={areas[n['area']]} other-map={areas.get(ar,ar)}: overlapping rectangles are not zone boundaries; verify best-map ownership in game")
    # Long border-to-border links may model real tunnels. Do NOT assume that a
    # cost of 0 makes a walk free: production LinkCost computes geometric cost.
    for line, f in links:
        if f[2] != "walk" or f[0] not in nodes or f[1] not in nodes:
            continue
        a, b = nodes[f[0]], nodes[f[1]]
        distance = math.hypot(a["p"][1] - b["p"][1], a["p"][2] - b["p"][2])
        if distance >= 300 and a["area"] != b["area"]:
            suspects.append(f"SUSPECT LONG_CONNECTION WaypointTracker/TravelData.lua:{line} entry={f[0]}>{f[1]} distance={distance:.1f} yd: explicit crossing trusted across unsampled terrain; retain if surveyed tunnel/road, otherwise add mouths and road bends; cost={f[3] or 'geometric'}")
    # Known-regression overlap points from the documented client replay.
    for m, x, y, expected_map in [(1416, .4805, .8221, 1424), (1416, .5869, .8036, 1424)]:
        expected = maps[expected_map]
        actual = area_at(m, x, y)
        if actual != expected:
            error("THRALL_OVERLAP", 0, f"map={m} ({x},{y})", areas.get(actual), f"documented Hillsbrad approach requires {areas[expected]}")
        runtime_input.append("\t".join(map(str, ["A", m, x, y, expected, "documented Thrall/Hillsbrad overlap"])))
    # Parent/child transform invariants in the independently extracted maps.
    for m, a in sorted(assignments.items()):
        parent = int(ui.get(m, {}).get("ParentUiMapID", 0))
        if parent not in assignments or assignments[parent]["cont"] != a["cont"]:
            continue
        for x, y in [(0, 0), (.5, .5), (1, 1), (.23, .81)]:
            pp = project(assignments[parent], world(a, x, y))
            back = project(a, world(assignments[parent], *pp))
            counts["parent_roundtrips"] += 1
            if math.hypot(back[0] - x, back[1] - y) > 1e-10:
                error("PARENT_TRANSFORM", 0, f"{m}>{parent}", back, "roundtrip fails")
    print(f"DATA maps={len(maps)} nodes={len(nodes)} regions={len(regions)} barriers={len(barriers)} continent0_maps={sum(assignments[m]['cont']==0 for m in maps)} continent1_maps={sum(assignments[m]['cont']==1 for m in maps)} sha256={hashlib.sha256(text.encode()).hexdigest()}")
    print("SAMPLES " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    for message in errors:
        print(message)
    for message in suspects:
        if args.details or "REGION_TRANSIT" in message or "LONG_CONNECTION" in message:
            print(message)
    if overlaps and not args.details:
        print(f"SUSPECT OVERLAP_AREA {len(overlaps)} map pairs, {sum(map(len, overlaps.values()))} disagreeing taxi projections (use --details); rectangles alone cannot establish ownership")
    print("COVERAGE all travel maps (long_graph = allowed same-area node chords >=1500 yards):")
    for m in sorted(maps):
        barrier_count = sum(bm == m for _, bm, _, _ in barriers)
        print(f"COVERAGE map={m} name={ui.get(m,{}).get('Name_lang','?')} barriers={barrier_count} regions={sum(r['m']==m for r in regions)} long_graph={per_map[m]['long_graph']} region_transit={per_map[m]['region_transit']}")
    runtime_failed = 0
    if not args.lua:
        print("FAIL RUNTIME_TOOL: install lua5.1 or provide --lua /path/to/lua; production planner was not checked")
        runtime_failed = 1
    else:
        print("RUNTIME_TOOL " + args.lua)
        if DATA.read_text(encoding="utf-8") != text:
            print("FAIL AUDIT_SNAPSHOT WaypointTracker/TravelData.lua changed during audit; rerun after generation settles")
            return 1
        result = subprocess.run([args.lua, str(ROOT / "tests/check_terrain_runtime.lua")],
            input="\n".join(runtime_input) + "\n", text=True, capture_output=True, cwd=ROOT, timeout=60)
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        runtime_failed = result.returncode != 0
        if DATA.read_text(encoding="utf-8") != text:
            print("FAIL AUDIT_SNAPSHOT WaypointTracker/TravelData.lua changed during Lua verification; rerun")
            runtime_failed = 1
    print(f"RESULT errors={len(errors)} suspect_groups={len(suspects)} runtime_failed={int(runtime_failed)}")
    return int(bool(errors or runtime_failed or (args.strict_suspects and suspects)))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError) as exc:
        print(f"FAIL AUDIT_INPUT {exc}", file=sys.stderr)
        sys.exit(1)
