#!/usr/bin/env python3
"""Precision-aware calibration and adaptive terrain routing, entirely offline.

Imports the independently implemented local CASC/ADT reader. Existing evidence
and files are read-only. Outputs are created exclusively, never overwritten.
Example:
  python3 tools/verify_legs_calibrated.py --output docs/terrain-calibrated.json \
    --summary docs/terrain-calibrated.tsv --detours tools/terrain_detours.tsv

PASSABLE is explicitly scoped to static terrain outside every evaluated object
bound, not doors, factions, moving platforms, or the player's current state.
Uncertain candidates are commented out in the consumable TSV. No Lua execution,
network, packages, game launch, client writes, or server is involved.
"""
import argparse
from collections import Counter
import csv
from functools import lru_cache
import hashlib
import heapq
import json
import math
from pathlib import Path
import re
import time

import verify_legs_terrain as old
from verify_legs_casc import LocalCASC, require

ROOT = old.ROOT
DIRS = old.DIRS


def checked(world, a, b):
    """The original strict geometry thresholds, with a named static-clear scope."""
    r = old.classify(world, dict(a=a, b=b))
    if r.get('reasons') == ['surface-clear-awaits-collision-or-continuous-ground-trace']:
        r.update(status='PASSABLE', reasons=[], issue_samples={})
    r['scope'] = 'exact chord; ADT ground, liquid, holes and placed-object bounding exclusions'
    return r


def unkey(k):
    return k // 4096 - 2048, k % 4096 - 2048


def key(x, y):
    return (x + 2048) * 4096 + y + 2048


def worldpoint(maps, mid, x, y, **extra):
    m = maps[mid]
    return dict(cont=int(m['MapID']), map=mid, x=x, y=y,
                wx=float(m['Region_3']) - y / 100 * (float(m['Region_3']) - float(m['Region_0'])),
                wy=float(m['Region_4']) - x / 100 * (float(m['Region_4']) - float(m['Region_1'])), **extra)


def mapcoords(maps, mid, x, y):
    m = maps[mid]
    return [mid, (float(m['Region_4']) - y) / (float(m['Region_4']) - float(m['Region_1'])) * 100,
            (float(m['Region_3']) - x) / (float(m['Region_3']) - float(m['Region_0'])) * 100]


def summaries(rows):
    return dict(Counter(r['status'] for r in rows))


def cell_control(world, cont, k, nk):
    """A cell transition is a region observation, never an exact center chord.

    Seek a compatible segment inside the two represented 20yd cells. A failed
    finite search cannot refute a recorded transition: it remains UNCERTAIN.
    This does not relax the exact-chord checker used for route legs/detours.
    """
    cx, cy = unkey(k); nx, ny = unkey(nk)
    a = dict(cont=cont, wx=(cx + .5) * 20, wy=(cy + .5) * 20)
    b = dict(cont=cont, wx=(nx + .5) * 20, wy=(ny + .5) * 20)
    center = checked(world, a, b)
    r = dict(id=f'{cont}:{k}:{nk}', cells=[[cx, cy], [nx, ny]],
             center_result=center, status='UNCERTAIN',
             precision_yards=math.sqrt(200), scope='observed cell transition, not exact chord',
             reason='quantization/interpolation and missing fall flags preclude exact-chord ground proof')
    if center['status'] != 'BLOCKED':
        r['compatible_chord'] = dict(a=a, b=b, offset=[0, 0], result=center)
        return r
    best = None
    for ox in [-8, -4, 0, 4, 8]:
        for oy in [-8, -4, 0, 4, 8]:
            pa = dict(a, wx=a['wx'] + ox, wy=a['wy'] + oy)
            pb = dict(b, wx=b['wx'] + ox, wy=b['wy'] + oy)
            q = checked(world, pa, pb)
            if q['status'] == 'BLOCKED':
                continue
            rank = (q['status'] != 'PASSABLE', q['max_slope_deg'])
            if best is None or rank < best[0]:
                best = rank, dict(a=pa, b=pb, offset=[ox, oy], result=q)
    if best:
        r['compatible_chord'] = best[1]
    return r


def calibration(world, saved_files, maps, source_nodes):
    controls = []; logs = []; snapshots = []; character_summaries = []
    seen = set()
    for p in saved_files:
        raw = p.read_bytes()
        parsed = old.SavedLiteralParser(raw.decode()).parse()
        snapshots.append(dict(role='character' if 'WaypointTrackerCharDB' in parsed else 'account',
                              bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                              mtime_epoch=p.stat().st_mtime))
        ch = parsed.get('WaypointTrackerCharDB', {})
        character_summaries.append(dict(travel_log_entries=len(ch.get('travelLog', {})),
                                       trail_cells=sum(len(g) for g in ch.get('trails', {}).get('own', {}).values())))
        db = parsed.get('WaypointTrackerDB', {})
        for cont, grid in db.get('trails', {}).get('own', {}).items():
            for k, bits in grid.items():
                cx, cy = unkey(k)
                for i, (dx, dy) in enumerate(DIRS):
                    nk = key(cx + dx, cy + dy)
                    ident = (cont, min(k, nk), max(k, nk))
                    if nk <= k or ident in seen or not bits & (1 << i) or not grid.get(nk, 0) & (1 << ((i + 4) % 8)):
                        continue
                    seen.add(ident); controls.append(cell_control(world, cont, k, nk))
        positions = []
        for row in db.get('travelLog', {}).values():
            m = re.match(r'(\d+) ([\d.]+) ([\d.]+) \| (\d+) (-?[\d.]+) (-?[\d.]+)', row.get('here', ''))
            if m:
                positions.append(dict(cont=int(m[4]), wx=float(m[5]), wy=float(m[6]), map=int(m[1]),
                                      when=row['when'], trail=bool(row.get('trail'))))
        for a, b in zip(positions, positions[1:]):
            if a['cont'] != b['cont']:
                continue
            distance = math.hypot(a['wx'] - b['wx'], a['wy'] - b['wy'])
            logs.append(dict(a=a, b=b, distance_yards=distance, seconds=b['when'] - a['when'],
                             result=checked(world, a, b), eligible_ground_control=False,
                             exclusion='log has no dead/ghost/taxi/boat/falling flag; sparse chord may cut a bend'))

    mz = {}
    for row in csv.reader((ROOT / 'tools/.cache/travel/mz_nodes.tsv').open(), delimiter='\t'):
        if row and row[3].isdigit() and int(row[3]) in maps:
            mz[row[0]] = worldpoint(maps, int(row[3]), float(row[4]) * 100, float(row[5]) * 100, id=row[0])
    source_controls = []
    for row in csv.reader((ROOT / 'tools/.cache/travel/mz_edges.tsv').open(), delimiter='\t'):
        if row[2] != 'walk' or row[0] not in mz or row[1] not in mz:
            continue
        a, b = mz[row[0]], mz[row[1]]
        if a['cont'] == b['cont'] and 1 < math.hypot(a['wx'] - b['wx'], a['wy'] - b['wy']) <= 100:
            source_controls.append(dict(id=row[0] + '>' + row[1], source='Mapzeroth explicit walk edge',
                                        a=a, b=b, result=checked(world, a, b),
                                        exact_chord_is_known_walked=False))
    for row in csv.reader((ROOT / 'tools/travel_extra.tsv').open(), delimiter='\t'):
        if len(row) < 5 or row[0] != 'link' or row[3] != 'walk':
            continue
        if row[1] not in source_nodes or row[2] not in source_nodes:
            continue
        a, b = source_nodes[row[1]], source_nodes[row[2]]
        source_controls.append(dict(id=row[1] + '>' + row[2], source='travel_extra explicit road/pass connection',
                                    a=a, b=b, result=checked(world, a, b), exact_chord_is_known_walked=False))
    patrol = []
    # Curated.lua encodes three Zixil patrol anchors, not a continuous trajectory.
    for x, y in [(50.4, 50.8), (55.6, 34.6), (60.8, 19.8)]:
        p = worldpoint(maps, 1424, x, y, id=f'Zixil-{x}-{y}')
        q = checked(world, p, p)
        patrol.append(dict(a=p, result=q, source='WaypointTracker_Data/Curated.lua NPC 3537',
                           limitation='anchor only; straight anchor-to-anchor line is not a positive control'))

    # Frozen independent negative controls, rather than choosing anew after calibration.
    a = worldpoint(maps, 1441, 45.0, 53.5, id='Freewind-mesa-south-valley')
    b = worldpoint(maps, 1441, 45.0, 50.0, id='Freewind-mesa-south-wall')
    peaks_a = worldpoint(maps, 1424, 60.2052, 18.7547, id='Tarren-Mill')
    peaks_b = worldpoint(maps, 1416, 61.5, 23.0, id='Strahnbrad-approach')
    negatives = [dict(id='thousand-needles-mesa-wall', a=a, b=b, result=checked(world, a, b)),
                 dict(id='alterac-tarren-mill-strahnbrad-ridge', a=peaks_a, b=peaks_b,
                      result=checked(world, peaks_a, peaks_b))]
    centered_bad = sum(r['center_result']['status'] == 'BLOCKED' for r in controls)
    return dict(saved_snapshots=snapshots, character_snapshots=character_summaries,
                own_transition_controls=controls, source_connection_controls=source_controls,
                zixil_anchor_controls=patrol, route_log_diagnostics=logs, negative_controls=negatives,
                summary=dict(own_reciprocal_undirected_transitions=len(controls),
                    naive_center_blocked=centered_bad,
                    naive_center_apparent_false_blocked_percent=round(100 * centered_bad / max(1, len(controls)), 4),
                    uncertainty_aware_false_blocked=0, uncertainty_aware_false_blocked_percent=0,
                    compatible_chord_witnesses=sum('compatible_chord' in r for r in controls),
                    exact_ground_controls_available=0,
                    physical_slope_limit_empirically_calibrated=False,
                    short_log_nonzero_chords=sum(0 < r['distance_yards'] <= 25 for r in logs),
                    short_log_blocked=sum(0 < r['distance_yards'] <= 25 and r['result']['status'] == 'BLOCKED' for r in logs),
                    source_connections=summaries([r['result'] for r in source_controls]),
                    zixil_anchors=summaries([r['result'] for r in patrol]),
                    negative_controls=summaries([r['result'] for r in negatives])),
                interpretation='0% is precision-aware cell-transition rejection, not a measured exact-footstep false-positive rate. '
                               'The center test is deliberately retained. Ghost corpse-run logs cannot calibrate alive movement; '
                               'Trails excludes ghost/swim/transport but not jumping/falling and interpolates up to 80yd.')


class AdaptivePaths:
    """Weighted A* with growing envelopes, fine grids and lazy dense refinement.

    Sparse checks are search accelerators only. Every returned chord undergoes
    full triangle-intersection/dense checking. Object-covered ground is allowed
    as UNCERTAIN with a cost penalty; it is never silently exported as validated.
    """
    def __init__(self, world, maps, road_edges):
        self.world = world; self.maps = maps; self.roads = {}
        for a, b in road_edges:
            if a['cont'] != b['cont']:
                continue
            if checked(world, a, b)['status'] == 'BLOCKED':
                continue
            for _, x, y in old.segment_points((a['wx'], a['wy']), (b['wx'], b['wy']), spacing=20):
                self.roads[(a['cont'], round(x / 25), round(y / 25))] = True

    @lru_cache(maxsize=250000)
    def sample(self, cont, x, y):
        return self.world.sample(cont, x, y)

    @staticmethod
    def state(s):
        if 'missing' in s:
            return 0
        uncertain = s['hole'] or s['objects'] or s['unknown']
        if not uncertain and (s['slope'] > 52 or any(w['min_depth'] > 2 for w in s['liquids'])):
            return 0
        if uncertain or s['slope'] > 45 or any(w['max_depth'] > .5 for w in s['liquids']):
            return 2
        return 1

    @lru_cache(maxsize=300000)
    def dense(self, cont, p, q):
        # Early termination is safe for failed edges. Full public results are
        # recomputed on final simplified/serialized routes, including endpoints.
        uncertain = False
        for _, x, y in old.segment_points(p, q):
            v = self.state(self.sample(cont, x, y))
            if not v:
                return 0
            uncertain |= v == 2
        return 2 if uncertain else 1

    def cheap(self, cont, p, q):
        states = [self.state(self.sample(cont, *r)) for r in
                  [p, q, ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)]]
        return max(states) if all(states) else 0

    def search(self, a, b, step, bounds, limit, known_bad):
        cont = a['cont']; ap = (a['wx'], a['wy']); bp = (b['wx'], b['wy'])
        lower = [math.floor(bounds[i] / step) for i in [0, 1]]
        upper = [math.ceil(bounds[i] / step) for i in [2, 3]]
        def xy(p): return p[0] * step, p[1] * step
        def neighbors_endpoint(p):
            center = round(p[0] / step), round(p[1] / step)
            choices = sorted(((center[0] + dx, center[1] + dy) for dx in range(-2, 3) for dy in range(-2, 3)),
                             key=lambda q: math.dist(xy(q), p))
            return {q: math.dist(p, xy(q)) for q in choices
                    if lower[0] <= q[0] <= upper[0] and lower[1] <= q[1] <= upper[1]
                    and self.cheap(cont, p, xy(q)) and self.dense(cont, p, xy(q))}
        starts = neighbors_endpoint(ap); goals = neighbors_endpoint(bp)
        if not starts or not goals:
            return None, 0, 'no densely validated endpoint connector at this resolution'
        costs = dict(starts); prev = {p: None for p in starts}; queue = []
        for p, g in starts.items():
            heapq.heappush(queue, (g + 1.35 * math.dist(xy(p), bp), g, p))
        expanded = 0
        while queue and expanded < limit:
            _, g, p = heapq.heappop(queue)
            if g != costs[p]: continue
            if p in goals:
                path = [p]
                while prev[p] is not None:
                    p = prev[p]; path.append(p)
                return [ap] + [xy(q) for q in reversed(path)] + [bp], expanded, None
            expanded += 1
            pp = xy(p)
            for dx, dy in DIRS:
                q = p[0] + dx, p[1] + dy
                if not (lower[0] <= q[0] <= upper[0] and lower[1] <= q[1] <= upper[1]): continue
                qp = xy(q); edge = tuple(sorted((pp, qp)))
                if edge in known_bad: continue
                v = self.cheap(cont, pp, qp)
                if not v: continue
                slope = self.sample(cont, *qp).get('slope', 90)
                multiplier = (1.6 if v == 2 else 1) + .1 * min(1, slope / 45)
                if (cont, round(qp[0] / 25), round(qp[1] / 25)) in self.roads:
                    multiplier *= .9
                ng = g + math.hypot(dx, dy) * step * multiplier
                if ng >= costs.get(q, math.inf): continue
                costs[q] = ng; prev[q] = p
                heapq.heappush(queue, (ng + 1.35 * math.dist(qp, bp), ng, q))
        return None, expanded, 'bounded search exhausted; not proof of disconnection'

    def simplify(self, cont, path):
        # Prefer proven static-clear shortcuts over object-covered shortcuts.
        result = [path[0]]; i = 0
        while i < len(path) - 1:
            end = min(len(path) - 1, i + 160); chosen = None
            for j in range(end, i, -1):
                if self.dense(cont, path[i], path[j]) == 1:
                    chosen = j; break
            if chosen is None:
                for j in range(end, i, -1):
                    if self.dense(cont, path[i], path[j]):
                        chosen = j; break
            require(chosen is not None, 'dense-valid path lost during simplification')
            result.append(path[chosen]); i = chosen
        return result

    def route(self, a, b):
        if a['cont'] != b['cont']:
            return dict(status='UNCERTAIN', reason='cross-instance endpoints', attempts=[])
        cont = a['cont']; ap = (a['wx'], a['wy']); bp = (b['wx'], b['wy'])
        attempts = []
        for endpoint in [ap, bp]:
            if self.state(self.sample(cont, *endpoint)) == 0:
                return dict(status='UNCERTAIN', reason='literal endpoint on blocked/missing ground; needs automatic floor/coordinate correction',
                            endpoint=endpoint, attempts=attempts)
        m = self.maps[a['map']]
        z = [float(m['Region_0']) - 150, float(m['Region_1']) - 150,
             float(m['Region_3']) + 150, float(m['Region_4']) + 150]
        full = [min(z[0], *[p[0] - 150 for p in [ap, bp]]), min(z[1], *[p[1] - 150 for p in [ap, bp]]),
                max(z[2], *[p[0] + 150 for p in [ap, bp]]), max(z[3], *[p[1] + 150 for p in [ap, bp]])]
        phases = [(25, 150, 12000), (25, 600, 24000), (12.5, 600, 30000),
                  (25, None, 45000), (12.5, None, 45000)]
        known_bad = set()
        for step, padding, limit in phases:
            bounds = full if padding is None else [min(ap[0], bp[0]) - padding, min(ap[1], bp[1]) - padding,
                                                    max(ap[0], bp[0]) + padding, max(ap[1], bp[1]) + padding]
            for repair in range(12):
                path, expanded, error = self.search(a, b, step, bounds, limit, known_bad)
                attempt = dict(grid_yards=step, envelope_yards=padding, bounds=bounds, expansion_limit=limit,
                               expanded=expanded, repair=repair, error=error)
                attempts.append(attempt)
                if path is None: break
                bad = []
                for p, q in zip(path, path[1:]):
                    if not self.dense(cont, p, q): bad.append(tuple(sorted((p, q))))
                attempt['dense_rejected_edges'] = len(bad)
                if bad:
                    known_bad.update(bad); continue
                simple = self.simplify(cont, path)
                # Serialize map coordinates FIRST, round-trip them, then validate
                # the exact values the builder would consume. No optimistic rounding.
                serialized = [mapcoords(self.maps, a['map'], *p) for p in simple]
                serialized = [[mid, round(x, 8), round(y, 8)] for mid, x, y in serialized]
                points = [worldpoint(self.maps, mid, x, y) for mid, x, y in serialized]
                points[0] = a; points[-1] = b
                segments = [checked(self.world, p, q) for p, q in zip(points, points[1:])]
                if any(r['status'] == 'BLOCKED' for r in segments):
                    attempt['error'] = 'serialized dense validation failed'; continue
                length = sum(math.hypot(p['wx'] - q['wx'], p['wy'] - q['wy']) for p, q in zip(points, points[1:]))
                return dict(status='PASSABLE' if all(r['status'] == 'PASSABLE' for r in segments) else 'UNCERTAIN',
                            reason='serialized candidate passes exact dense terrain checker; inspect segment statuses for static collision uncertainty',
                            scope='static terrain candidate; object/hole/coverage uncertainty is not walkability proof',
                            length_yards=round(length, 3), straight_ratio=round(length / max(.001, math.dist(ap, bp)), 5),
                            waypoints_world=[[p['wx'], p['wy']] for p in points], waypoints_map=serialized,
                            segments=segments, segment_counts=summaries(segments), attempts=attempts,
                            source='same-build local ADT heights/liquids/holes, placement exclusions; source-connection cost preference')
        return dict(status='UNCERTAIN', reason='adaptive searches exhausted; collision floor or finer navmesh needed', attempts=attempts)


def area_names():
    s = (ROOT / 'WaypointTracker/TravelData.lua').read_text()
    m = re.search(r'\bareas\s*=\s*\{(.*?)\}', s, re.S)
    require(m is not None, 'missing TravelData area names')
    return {i: name for i, name in enumerate(re.findall(r'"([^"\n]+)"', m[1]), 1)}


def detour_tsv(path, records, areas, maps):
    """Both active and commented rows use unmodified travel_extra.tsv syntax."""
    out = ['# Generated by verify_legs_calibrated.py; client 1.60.1.70338.',
           '# Only all-PASSABLE static-clear chains are active. UNCERTAIN chains are commented proposals.',
           '# Import with existing travel_extra.tsv; never use this alone as TRAVEL_EXTRA.',
           '# Build/planner integration MUST suppress each replaced implicit chord and forbid unchecked shortcuts.']
    unique = {}; exported = []
    for r in records:
        q = r.get('replacement', {})
        if not q.get('waypoints_map'): continue
        ident = tuple(sorted((r['a']['id'], r['b']['id'])))
        if ident in unique: continue
        digest = hashlib.sha256('|'.join(ident).encode()).hexdigest()[:12].upper()
        unique[ident] = digest
        active = q['status'] == 'PASSABLE'
        prefix = '' if active else '# PROPOSAL\t'
        out.append(f"# {digest}: {r['id']} status={q['status']} ratio={q['straight_ratio']} segment_counts={json.dumps(q['segment_counts'], sort_keys=True)}")
        ids = [r['a']['id']]
        container = areas.get(r['a'].get('area'), 'easternkingdoms.hillsbrad_foothills')
        # Some synthetic road points carry no area; all original review nodes do.
        for i, (mid, x, y) in enumerate(q['waypoints_map'][1:-1], 1):
            nid = f'TERRAIN_{digest}_{i:02d}'; ids.append(nid)
            # Full-zone searches can cross an adjacent map's edge. Reproject to
            # a matching outdoor map, rather than truncating/clamping the path.
            if not (0 <= x <= 100 and 0 <= y <= 100):
                wp = worldpoint(maps, mid, x, y)
                candidates = []
                for other in maps:
                    if other not in {1411, 1412, 1413, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424,
                                     1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436,
                                     1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1446, 1447, 1448, 1449,
                                     1450, 1451, 1452, 2548, 2652} or int(maps[other]['MapID']) != wp['cont']:
                        continue
                    _, ox, oy = mapcoords(maps, other, wp['wx'], wp['wy'])
                    if 0 <= ox <= 100 and 0 <= oy <= 100:
                        candidates.append((other, ox, oy))
                require(bool(candidates), 'no outdoor map covers detour waypoint')
                mid, x, y = candidates[0]
            out.append(prefix + '\t'.join(['node', nid, 'pass', container, str(mid), f'{x:.8f}', f'{y:.8f}',
                                          f'Local CASC 70338 terrain {digest}; {q["status"]}; docs/terrain-calibrated.json']))
        ids.append(r['b']['id'])
        for x, y in zip(ids, ids[1:]): out.append(prefix + '\t'.join(['link', x, y, 'walk', '0']))
        exported.append(dict(id=r['id'], chain=digest, status=q['status'], active=active, node_ids=ids))
    path.write_text('\n'.join(out) + '\n')
    return exported


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--install', default='/Applications/World of Warcraft')
    ap.add_argument('--input', type=Path, default=ROOT / 'docs/terrain-leg-evidence.json')
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--summary', type=Path, required=True)
    ap.add_argument('--detours', type=Path, required=True)
    ap.add_argument('--no-paths', action='store_true')
    ap.add_argument('--reuse-proposals', type=Path, help='Revalidate this tool\'s prior proposals instead of repeating A*')
    ap.add_argument('--progress', type=Path, help='New progress checkpoint outside client')
    args = ap.parse_args(); start = time.monotonic()
    outputs = [args.output, args.summary, args.detours] + ([args.progress] if args.progress else [])
    for p in outputs:
        require(not p.exists() and not p.resolve().is_relative_to(Path(args.install).resolve()), 'output must be new and outside client')
        p.parent.mkdir(parents=True, exist_ok=True)
    # Freeze all original coordinates, even while another executor changes TravelData.
    frozen = json.loads(args.input.read_text()); legs = [{k: r[k] for k in ['id', 'kind', 'a', 'b']} for r in frozen['records']]
    require(sum(r['kind'] == 'review-leg' for r in legs) == 137, 'expected original 137 review legs')
    with (ROOT / 'tools/fixtures/travel/UiMapAssignment.csv').open() as stream:
        maps = {int(r['UiMapID']): r for r in csv.DictReader(stream) if r['UiMin_0'] == '0' and r['UiMax_0'] == '1'}
    paths = ['tools/verify_legs_casc.py', 'tools/verify_legs_terrain.py', 'tools/verify_legs_calibrated.py',
             'tools/fixtures/travel/Map.csv', 'tools/fixtures/travel/UiMapAssignment.csv',
             'tools/.cache/travel/mz_nodes.tsv', 'tools/.cache/travel/mz_edges.tsv',
             'tools/travel_extra.tsv', 'WaypointTracker/Trails.lua', 'WaypointTracker/TravelData.lua', 'WaypointTracker_Data/Curated.lua']
    hashes = {p: old.sha(ROOT / p) for p in paths}
    areas = area_names()
    casc = LocalCASC(args.install)
    require(casc.build['Version!STRING:0'] == '1.60.1.70338', 'pinned fixture/client version mismatch')
    world = old.World(casc)
    saved = list((Path(args.install) / '_classic_beta_/WTF/Account').glob('*/SavedVariables/WaypointTracker.lua'))
    if saved:
        account = max(saved, key=lambda p: p.stat().st_mtime)
        saved = [account] + list(account.parents[1].glob('*/*/SavedVariables/WaypointTracker.lua'))
    print('Calibrating movement and source controls', flush=True)
    data_text = (ROOT / 'WaypointTracker/TravelData.lua').read_text()
    source_nodes = {row[0]: dict(id=row[0], cont=int(row[3]), wx=float(row[4]), wy=float(row[5]),
                               map=int(row[6]), x=float(row[7]), y=float(row[8]))
                    for row in old.tsv_block(data_text, 'nodes')}
    cal = calibration(world, saved, maps, source_nodes)
    print('Calibration:', json.dumps(cal['summary'], sort_keys=True), flush=True)
    require(all(r['result']['status'] == 'BLOCKED' for r in cal['negative_controls']), 'negative control lost: investigate before routing')
    records = []
    for i, r in enumerate(legs):
        records.append(dict(r, **checked(world, r['a'], r['b'])))
        if (i + 1) % 10 == 0: print('Classified', i + 1, summaries(records), flush=True)
    source_edges = [(r['a'], r['b']) for r in cal['source_connection_controls'] if r['result']['status'] != 'BLOCKED']
    routes = AdaptivePaths(world, maps, source_edges)
    unique = {}
    reused = {}
    if args.reuse_proposals:
        prior = json.loads(args.reuse_proposals.read_text())
        require(prior['schema'] == 'wt-terrain-calibrated-v2' and prior['build'] == frozen['build'],
                'proposal build/schema mismatch')
        for row in prior['records']:
            if row.get('replacement'):
                reused[row['id']] = row
    if not args.no_paths:
        for r in records:
            if r['status'] != 'BLOCKED' or r['kind'] not in {'review-leg', 'road-approach'}: continue
            ident = tuple(sorted((r['a']['id'], r['b']['id'])))
            if ident not in unique:
                print('Adaptive route', len(unique) + 1, r['id'], flush=True)
                if r['id'] in reused:
                    earlier = reused[r['id']]
                    require(earlier['a'] == r['a'] and earlier['b'] == r['b'], 'reused proposal endpoints changed')
                    q = dict(earlier['replacement'])
                    if q.get('waypoints_world'):
                        points = [dict(r['a'], wx=x, wy=y) for x, y in q['waypoints_world']]
                        segments = [checked(world, p, s) for p, s in zip(points, points[1:])]
                        require(all(s['status'] != 'BLOCKED' for s in segments), 'proposal failed fresh strict validation')
                        q.update(segments=segments, segment_counts=summaries(segments),
                                 status='PASSABLE' if all(s['status'] == 'PASSABLE' for s in segments) else 'UNCERTAIN',
                                 freshly_revalidated=True)
                else:
                    q = routes.route(r['a'], r['b'])
                q['from'] = r['a']['id']; q['to'] = r['b']['id']
                unique[ident] = q
                print('Result', q['status'], len(q.get('waypoints_world', [])), q['reason'], flush=True)
                if args.progress:
                    args.progress.write_text(json.dumps(dict(calibration=cal, records=records, routes=list(unique.values())), indent=2))
            q = dict(unique[ident])
            if q['from'] != r['a']['id']:
                for field in ['waypoints_world', 'waypoints_map', 'segments']:
                    if field in q: q[field] = list(reversed(q[field]))
                q['from'] = r['a']['id']; q['to'] = r['b']['id']
            r['replacement'] = q
    exports = detour_tsv(args.detours, records, areas, maps)
    counts = {k: summaries([r for r in records if r['kind'] == k]) for k in sorted({r['kind'] for r in records})}
    targets = [r for r in records if r['kind'] == 'review-leg' and r['status'] == 'BLOCKED']
    proposals = [r for r in targets if r.get('replacement', {}).get('waypoints_map')]
    output = dict(schema='wt-terrain-calibrated-v2', build=frozen['build'], frozen_input_sha256=old.sha(args.input),
                  original_coordinate_input_sha256=frozen['input_sha256'], read_input_sha256=hashes,
                  concurrent_inputs_changed=[p for p, h in hashes.items() if old.sha(ROOT / p) != h],
                  calibration=cal, records=records, counts_by_kind=counts,
                  detour_summary=dict(blocked_review_legs=len(targets), candidates=len(proposals),
                    coverage_percent=round(100 * len(proposals) / max(1, len(targets)), 3),
                    all_static_clear=sum(r['replacement']['status'] == 'PASSABLE' for r in proposals),
                    uncertain_candidates=sum(r['replacement']['status'] == 'UNCERTAIN' for r in proposals),
                    unique_exported_chains=len(exports), active_exported_chains=sum(r['active'] for r in exports)),
                  detour_exports=exports, client_content_manifest=casc.manifest, extraction_errors=world.errors,
                  parameters=dict(sample_yards=2, blocked_slope_deg=52, static_clear_slope_deg=45,
                    deep_liquid_lower_bound_yards=2, static_clear_liquid_upper_bound_yards=.5,
                    object_margin_yards=old.MARGIN, astar_weight=1.35,
                    adaptive_search_phases=[dict(grid_yards=g, padding_yards=p, limit=n) for g, p, n in
                      [(25, 150, 12000), (25, 600, 24000), (12.5, 600, 30000), (25, None, 45000), (12.5, None, 45000)]],
                    dense_refinement_rounds=12, source_connection_cost_multiplier=.9,
                    proposal_revalidation_source_sha256=old.sha(args.reuse_proposals) if args.reuse_proposals else None),
                  runtime_seconds=round(time.monotonic() - start, 2),
                  semantics=dict(PASSABLE='Static-clear exact chord outside all evaluated object bounds, slope <=45deg, liquid depth <=0.5yd, no holes/unknown coverage.',
                    BLOCKED='Exact bare-ground chord has terrain >52deg or liquid lower-bound depth >2yd; not destination unreachable.',
                    UNCERTAIN='Object floor/collision, holes, unknown coverage, 45..52deg slope, liquid, or region-only movement evidence.',
                    calibration='Physical slope threshold is not empirically proved by quantized observations; no threshold relaxation.'))
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + '\n')
    old.write_summary(args.summary, output)
    print(json.dumps(dict(counts=counts, detours=output['detour_summary'], runtime_seconds=output['runtime_seconds']), sort_keys=True), flush=True)


if __name__ == '__main__':
    main()
