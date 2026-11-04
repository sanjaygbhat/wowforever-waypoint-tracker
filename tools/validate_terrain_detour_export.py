#!/usr/bin/env python3
"""Validate detours AFTER the current builder's coordinate rounding.

Writes a new travel_extra-compatible TSV. Static-clear subsegments are active;
uncertain segments are commented. Full routes are never activated by merely
passing through object bounding boxes. Uses both native-map and world-fallback
coordinates, and the CURRENT endpoint definitions from TravelData.lua.

python3 tools/validate_terrain_detour_export.py --input docs/terrain-calibrated.json \
 --output docs/terrain-consumer-check.json --detours tools/terrain_detours_ready.tsv
"""
import argparse
from collections import Counter
import csv
import hashlib
import heapq
import json
import math
from pathlib import Path
import time

import verify_legs_terrain as old
from verify_legs_calibrated import checked, worldpoint, mapcoords, area_names
from verify_legs_casc import LocalCASC, require

OUTDOOR = set(range(1411, 1453)) | {2548, 2652}


def projected(maps, mid, wx, wy):
    first = mapcoords(maps, mid, wx, wy)
    if 0 <= first[1] <= 100 and 0 <= first[2] <= 100:
        return first
    choices = [mapcoords(maps, other, wx, wy) for other in sorted(OUTDOOR & set(maps))
               if maps[other]['MapID'] == maps[mid]['MapID']]
    choices = [p for p in choices if 0 <= p[1] <= 100 and 0 <= p[2] <= 100]
    require(bool(choices), 'no outdoor map for world point')
    return choices[0]


def consumer_point(maps, mid, x, y):
    # build_travel.py computes fallback world coordinates BEFORE rounding map %.
    raw = worldpoint(maps, mid, x, y)
    return dict(map_point=worldpoint(maps, mid, float(f'{x:.2f}'), float(f'{y:.2f}')),
                fallback_point=dict(raw, wx=float(f'{raw["wx"]:.1f}'), wy=float(f'{raw["wy"]:.1f}')),
                map_row=[mid, float(f'{x:.2f}'), float(f'{y:.2f}')])


def bridge_rounded_segment(world, maps, a, b, validate):
    """Repair an edge on the actual consumer grid; no optimistic resampling.

    Search points are rounded map percentages before testing, including fallback
    coordinates. Every connector, grid edge and simplification shortcut uses
    the two-representation validator. A failed search is left commented out.
    """
    ap = a['map_point']['wx'], a['map_point']['wy']
    bp = b['map_point']['wx'], b['map_point']['wy']
    mid = a['map_row'][0]; cont = a['map_point']['cont']; step = 5
    cache = {}; edge_cache = {}
    def point(p):
        if p not in cache:
            m, x, y = projected(maps, mid, p[0] * step, p[1] * step)
            cache[p] = consumer_point(maps, m, round(x, 2), round(y, 2))
        return cache[p]
    def edge(p, q):
        ident = (tuple(p['map_row']), tuple(q['map_row']))
        if ident not in edge_cache:
            # Reject impossible endpoints cheaply before full dense validation.
            from verify_legs_calibrated import AdaptivePaths
            valid = all(AdaptivePaths.state(world.sample(cont, v['wx'], v['wy']))
                        for v in [p['map_point'], q['map_point'], p['fallback_point'], q['fallback_point']])
            edge_cache[ident] = validate(p, q)['status'] if valid else 'BLOCKED'
        return edge_cache[ident]
    def xy(p): return p[0] * step, p[1] * step
    for padding, limit in [(30, 8000), (100, 16000), (300, 30000)]:
        lower = [math.floor((min(ap[i], bp[i]) - padding) / step) for i in [0, 1]]
        upper = [math.ceil((max(ap[i], bp[i]) + padding) / step) for i in [0, 1]]
        def attached(endpoint, pos):
            center = round(pos[0] / step), round(pos[1] / step)
            choices = [(center[0] + dx, center[1] + dy) for dx in range(-2, 3) for dy in range(-2, 3)]
            return {p: math.dist(xy(p), pos) for p in choices if edge(endpoint, point(p)) != 'BLOCKED'}
        starts = attached(a, ap); goals = attached(b, bp)
        costs = dict(starts); previous = {p: None for p in starts}
        queue = [(g + 1.3 * math.dist(xy(p), bp), g, p) for p, g in starts.items()]; heapq.heapify(queue)
        expanded = 0
        while queue and expanded < limit:
            _, g, p = heapq.heappop(queue)
            if g != costs[p]: continue
            if p in goals:
                path = [p]
                while previous[p] is not None: p = previous[p]; path.append(p)
                points = [a] + [point(q) for q in reversed(path)] + [b]
                result = [points[0]]; i = 0
                while i < len(points) - 1:
                    j = min(len(points) - 1, i + 120)
                    while j > i + 1 and edge(points[i], points[j]) == 'BLOCKED': j -= 1
                    require(edge(points[i], points[j]) != 'BLOCKED', 'rounded path shortcut failed')
                    result.append(points[j]); i = j
                return result
            expanded += 1
            for dx, dy in old.DIRS:
                q = p[0] + dx, p[1] + dy
                if not (lower[0] <= q[0] <= upper[0] and lower[1] <= q[1] <= upper[1]): continue
                baseline = g + step * math.hypot(dx, dy)
                if baseline >= costs.get(q, math.inf): continue
                status = edge(point(p), point(q))
                if status == 'BLOCKED': continue
                ng = g + step * math.hypot(dx, dy) * (1.3 if status == 'UNCERTAIN' else 1)
                if ng >= costs.get(q, math.inf): continue
                costs[q] = ng; previous[q] = p
                heapq.heappush(queue, (ng + 1.3 * math.dist(xy(q), bp), ng, q))
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--install', default='/Applications/World of Warcraft')
    ap.add_argument('--input', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--detours', type=Path, required=True)
    args = ap.parse_args(); started = time.monotonic()
    for p in [args.output, args.detours]:
        require(not p.exists() and not p.resolve().is_relative_to(Path(args.install).resolve()), 'output must be new and outside client')
        p.parent.mkdir(parents=True, exist_ok=True)
    data = json.loads(args.input.read_text())
    with (old.ROOT / 'tools/fixtures/travel/UiMapAssignment.csv').open() as stream:
        maps = {int(r['UiMapID']): r for r in csv.DictReader(stream) if r['UiMin_0'] == '0' and r['UiMax_0'] == '1'}
    live_path = old.ROOT / 'WaypointTracker/TravelData.lua'; raw = live_path.read_text(); live_sha = old.sha(live_path)
    current = {r[0]: dict(id=r[0], cont=int(r[3]), wx=float(r[4]), wy=float(r[5]), map=int(r[6]),
                         x=float(r[7]), y=float(r[8]), area=int(r[2])) for r in old.tsv_block(raw, 'nodes')}
    areas = area_names(); casc = LocalCASC(args.install)
    require(casc.build['Version!STRING:0'] == data['build']['version'], 'client version mismatch')
    world = old.World(casc)
    output = ['# NEW supplemental travel_extra.tsv rows; build 1.60.1.70338.',
              '# Both CURRENT map-coordinate and world-fallback representations checked AFTER builder rounding.',
              '# Active rows are static-clear SUBSEGMENTS. Commented gaps prevent uncertified whole-chain activation.',
              '# Merge with existing extras; gate implicit walking/shortcuts using evidence before enabling.',
              f'# Source and exact statuses: {args.output.name}. No new guessed barriers.']
    unique = set(); results = []; active_segments = 0; active_nodes = set(); full_routes = 0
    for r in data['records']:
        proposal = r.get('replacement', {})
        if not proposal.get('waypoints_world'): continue
        ident = tuple(sorted((r['a']['id'], r['b']['id'])))
        if ident in unique: continue
        unique.add(ident); digest = hashlib.sha256('|'.join(ident).encode()).hexdigest()[:12].upper()
        a, b = current[r['a']['id']], current[r['b']['id']]
        projected_points = [projected(maps, a['map'], x, y) for x, y in proposal['waypoints_world'][1:-1]]
        # Persist already-rounded percentages so input and output maps coincide.
        points = [consumer_point(maps, p[0], round(p[1], 2), round(p[2], 2)) for p in projected_points]
        endpoints = []
        for n in [a, b]:
            endpoints.append(dict(map_point=worldpoint(maps, n['map'], n['x'], n['y']),
                                  fallback_point=n, map_row=[n['map'], n['x'], n['y']]))
        points = [endpoints[0]] + points + [endpoints[1]]

        def validate(p, q):
            native = checked(world, p['map_point'], q['map_point'])
            fallback = checked(world, p['fallback_point'], q['fallback_point'])
            statuses = {native['status'], fallback['status']}
            status = 'BLOCKED' if 'BLOCKED' in statuses else 'UNCERTAIN' if 'UNCERTAIN' in statuses else 'PASSABLE'
            return dict(status=status, native=native, fallback=fallback)

        segments = [validate(p, q) for p, q in zip(points, points[1:])]
        before = sum(s['status'] == 'BLOCKED' for s in segments)
        repairs = []
        for iteration in range(3):
            if not any(s['status'] == 'BLOCKED' for s in segments): break
            changed = False
            for i in range(1, len(points) - 1):
                if segments[i - 1]['status'] != 'BLOCKED' and segments[i]['status'] != 'BLOCKED': continue
                mid, x, y = points[i]['map_row']; best = None
                for dx in [-.02, -.01, 0, .01, .02]:
                    for dy in [-.02, -.01, 0, .01, .02]:
                        if not (0 <= x + dx <= 100 and 0 <= y + dy <= 100): continue
                        p = consumer_point(maps, mid, round(x + dx, 2), round(y + dy, 2))
                        left, right = validate(points[i - 1], p), validate(p, points[i + 1])
                        if left['status'] == 'BLOCKED' or right['status'] == 'BLOCKED': continue
                        rank = (sum(s['status'] == 'UNCERTAIN' for s in [left, right]), dx * dx + dy * dy)
                        if best is None or rank < best[0]: best = rank, p, left, right
                if best:
                    _, p, left, right = best
                    repairs.append(dict(index=i, before=points[i]['map_row'], after=p['map_row']))
                    points[i] = p; segments[i - 1] = left; segments[i] = right; changed = True
            if not changed: break
        # Remaining rounding slivers get real detours on the rounded consumer
        # grid. Do not raise the slope limit or forgive narrow blocked triangles.
        bridged = []; rounding_bridges = []
        for i, (p, q) in enumerate(zip(points, points[1:])):
            if not bridged: bridged.append(p)
            if validate(p, q)['status'] == 'BLOCKED':
                bridge = bridge_rounded_segment(world, maps, p, q, validate)
                if bridge:
                    rounding_bridges.append(dict(original_segment=i, inserted=len(bridge) - 2))
                    bridged.extend(bridge[1:]); continue
            bridged.append(q)
        points = bridged
        # Recheck the final sequence together; repairs never rely on stale edges.
        segments = [validate(p, q) for p, q in zip(points, points[1:])]
        ids = [a['id']] + [f'TERRAIN_{digest}_{i:02d}' for i in range(1, len(points) - 1)] + [b['id']]
        pass_indices = {i for i, s in enumerate(segments) if s['status'] == 'PASSABLE'}
        used = {j for i in pass_indices for j in [i, i + 1]}
        container = areas[a['area']]
        output.append(f'# {digest} {r["id"]}; consumer statuses {json.dumps(dict(Counter(s["status"] for s in segments)), sort_keys=True)}')
        for i, p in enumerate(points[1:-1], 1):
            mid, x, y = p['map_row']; prefix = '' if i in used else '# PROPOSAL\t'
            output.append(prefix + '\t'.join(['node', ids[i], 'pass', container, str(mid), f'{x:.2f}', f'{y:.2f}',
                                              f'CASC70338 {digest}; static-clear subsegments only; {args.output.name}']))
            if i in used: active_nodes.add(ids[i])
        for i, (x, y) in enumerate(zip(ids, ids[1:])):
            prefix = '' if i in pass_indices else '# ' + segments[i]['status'] + '\t'
            output.append(prefix + '\t'.join(['link', x, y, 'walk', '0']))
        active_segments += len(pass_indices); full = len(pass_indices) == len(segments); full_routes += full
        results.append(dict(id=r['id'], chain=digest, node_ids=ids, map_points=[p['map_row'] for p in points],
                            segment_results=segments, active_segment_indices=sorted(pass_indices),
                            full_chain_static_clear=full, blocked_before_rounding_repair=before,
                            rounding_repairs=repairs, rounding_bridges=rounding_bridges,
                            frozen_endpoint_deltas_yards=[math.hypot(n['wx'] - original['wx'], n['wy'] - original['wy'])
                                                          for n, original in [(a, r['a']), (b, r['b'])]]))
        print('Consumer checked', len(results), digest, dict(Counter(s['status'] for s in segments)), flush=True)
    require(old.sha(live_path) == live_sha, 'TravelData changed concurrently: rerun consumer check on stable snapshot')
    args.detours.write_text('\n'.join(output) + '\n')
    summary = dict(unique_candidate_chains=len(results), full_static_clear_chains=full_routes,
                   active_static_clear_subsegments=active_segments, active_intermediate_nodes=len(active_nodes),
                   consumer_blocked_chains=sum(any(s['status'] == 'BLOCKED' for s in r['segment_results']) for r in results),
                   repaired_waypoints=sum(len(r['rounding_repairs']) for r in results),
                   repaired_segments=sum(len(r['rounding_bridges']) for r in results),
                   runtime_seconds=round(time.monotonic() - started, 2))
    args.output.write_text(json.dumps(dict(schema='wt-terrain-consumer-check-v1', summary=summary, chains=results,
        input_sha256=old.sha(args.input), current_traveldata_sha256=live_sha,
        tool_sha256=old.sha(__file__), output_tsv_sha256=old.sha(args.detours),
        client_content_manifest=casc.manifest, extraction_errors=world.errors), indent=2, sort_keys=True) + '\n')
    print(json.dumps(summary, sort_keys=True), flush=True)


if __name__ == '__main__': main()
