"""Apply frozen, build-specific verdicts before travel serialization."""
import hashlib
import gzip
import json
from collections import defaultdict


def compile_verified(root, node_lines, links, pending, to_map, area_at):
    path = root / 'tools/fixtures/travel/verified-routing.json'
    policy = json.loads(path.read_text())
    assert policy['build'] == '1.60.1.70338', 'verification build changed'
    source = hashlib.sha256(path.read_bytes()).hexdigest()
    rows = {r.split('\t')[0]: r.split('\t') for r in node_lines + pending}
    moved = {r['id'] for r in policy['transport'] if r['values'].get('exact_trigger')}
    for r in policy['baseline_nodes']:
        if r[0] in rows and r[0] not in moved:
            if rows[r[0]][3:9] != r[3:9]:
                raise ValueError('verified endpoint changed: ' + r[0])
    # Apply measured border corrections after checking the frozen input anchors.
    # Incident verdicts and replacement endpoints use these exact representations.
    corrections = policy.get('border_corrections', {})
    if corrections:
        raw = (root / 'tools/fixtures/travel/border-evidence.json.gz').read_bytes()
        assert hashlib.sha256(raw).hexdigest() == policy['border_evidence_sha256'], 'stale border evidence'
        borders = json.loads(gzip.decompress(raw))
        assert borders['build'] == policy['build'], 'border evidence build changed'
        endpoints = {}
        for record in borders['search']['records']:
            if record['verdict'] != 'VERIFIED-WALKABLE':
                continue
            assert all(s['verdict'] == 'VERIFIED-WALKABLE' and s['world']['status'] == s['native']['status'] == 'PASSABLE'
                       for s in record['segments']), 'unverified border chord: ' + record['id']
            for original, point in zip((record['original_a'], record['original_b']), (record['points'][0], record['points'][-1])):
                endpoints[original['id']] = [str(point[k]) for k in ('cont', 'wx', 'wy', 'map', 'x', 'y')]
    for nid, position in corrections.items():
        assert nid in rows and len(position) == 6, 'invalid border correction: ' + nid
        assert position == endpoints[nid], 'border correction differs from proof: ' + nid
        rows[nid][3:9] = position
    verdicts = {(r['kind'], r['from_id'], r['to_id']): r for r in policy['walk']}
    evidence, kept, labels = {}, [], []
    retain = policy['retain_unmeasured']

    def emit(a, b, state, provenance, chain=''):
        if a not in rows or b not in rows:
            return
        positions = rows[a][3:9] + rows[b][3:9]
        fingerprint = hashlib.sha256('\t'.join(positions).encode()).hexdigest()
        evidence[a, b] = '\t'.join([a, b, state, provenance, policy['build'],
                                    fingerprint, source, chain] + positions)

    unmeasured = {r['id'].replace('->', '>'): 'unmeasured-traversal'
                  for r in policy['transport'] if r['verdict'] == 'UNVERIFIABLE'}
    for link in links:
        a, b, method = link[:3]
        key = a + '>' + b
        if method == 'walk':
            record = verdicts.get(('link', a, b))
            if not record:
                raise ValueError('missing walking verdict: ' + key)
            if record['verdict'] == 'BLOCKED':
                emit(a, b, 'TERRAIN_BLOCKED', 'terrain-static,client-collision')
                continue
            if record['verdict'] == 'UNVERIFIABLE':
                if a.startswith('TERRAIN_') or b.startswith('TERRAIN_'):
                    continue  # Unmeasured detour pieces are never retained.
                unmeasured[key] = 'unmeasured-indoor' if 'SANCTUM' in key or 'BLACKROCK' in key else 'unmeasured'
            else:
                emit(a, b, 'TERRAIN_CLEAR', 'terrain-static,client-collision')
        if key in unmeasured:
            label = unmeasured[key]
            if retain is not None and key not in retain:
                emit(a, b, 'UNAVAILABLE', label)
                continue
            emit(a, b, 'UNCERTAIN', label)
            labels.append('\t'.join([a, b, method, label]))
        kept.append(link)

    # Preserve refuted original shortcuts so implicit same-area walking cannot
    # recreate a removed BLOCKED edge after its explicit row has gone.
    for r in policy['walk']:
        a, b = r['from_id'], r['to_id']
        if r['kind'] == 'pending-link' and r['verdict'] == 'VERIFIED-WALKABLE':
            emit(a, b, 'TERRAIN_CLEAR', 'terrain-static,client-collision')
            kept.append([a, b, 'walk', '0', '', '', '', '', '', '', ''])
        if r['kind'] in ('proof-link', 'review-leg', 'road-approach', 'pending-link') and r['verdict'] == 'BLOCKED':
            emit(a, b, 'TERRAIN_BLOCKED', 'terrain-static,client-collision')

    # Exact joins only. Different rounded/native representations are not merged.
    coordinates = {(int(r[3]), float(r[4]), float(r[5]), int(r[6]), float(r[7]), float(r[8])): nid for nid, r in rows.items()}
    groups = defaultdict(list)
    for point in policy['replacements']:
        groups[point['replacement_id']].append(point)
    for rid, points in sorted(groups.items()):
        points.sort(key=lambda p: int(p['sequence']))
        assert [int(p['sequence']) for p in points] == list(range(len(points))), rid
        a, b, kind = points[0]['from_id'], points[0]['to_id'], points[0]['original_kind']
        if kind not in ('link', 'pending-link', 'proof-link', 'review-leg', 'road-approach', 'consumer-chain', 'detour-104', 'route-control'):
            continue
        if a not in rows or (b not in rows and kind != 'route-control'):
            continue
        area = rows[a][2]
        ids = []
        for i, p in enumerate(points):
            key = (int(p['continent']), float(p['world_x']), float(p['world_y']), int(p['map']), float(p['map_x']), float(p['map_y']))
            nid = a if i == 0 else b if i == len(points)-1 and b in rows else coordinates.get(key)
            if nid is None:
                nid = 'TERRAIN_VERIFIED_' + p['point_id'].removeprefix('GEOM_')
                point_area, city = area_at(int(p['map']), float(p['map_x'])/100, float(p['map_y'])/100)
                rows[nid] = [nid, 'pass', str(point_area), p['continent'], p['world_x'], p['world_y'],
                             p['map'], p['map_x'], p['map_y'], str(city or ''), '', '', '']
                coordinates[key] = nid
            else:
                assert (int(rows[nid][3]), float(rows[nid][4]), float(rows[nid][5])) == key[:3], 'replacement endpoint changed: ' + nid
                assert int(rows[nid][6]) == int(p['map']) and float(rows[nid][7]) == float(p['map_x']) and float(rows[nid][8]) == float(p['map_y']), 'replacement map endpoint changed: ' + nid
            ids.append(nid)
        for a, b in zip(ids, ids[1:]):
            if a == b:
                continue
            emit(a, b, 'TERRAIN_CLEAR', 'terrain-static,client-collision', rid)
            kept.append([a, b, 'walk', '0', '', '', '', '', '', '', ''])

    # Keep every verified local connection, including usable fragments whose
    # distant continuation is unmeasured. Isolated points grant no routing.
    graph = defaultdict(set)
    for link in kept:
        if link[2] == 'walk':
            graph[link[0]].add(link[1]); graph[link[1]].add(link[0])
    usable, visited = set(), set()
    for nid in sorted(graph):
        if nid in visited:
            continue
        component, todo = set(), [nid]
        while todo:
            n = todo.pop()
            if n in component:
                continue
            component.add(n); todo.extend(graph[n] - component)
        visited.update(component)
        if len(component) >= 2:
            usable.update(component)
    rows = {nid: r for nid, r in rows.items() if not nid.startswith('TERRAIN_') or nid in usable}
    unique = {}
    for link in kept:
        if link[0] in rows and link[1] in rows:
            unique[tuple(link)] = link
    kept = list(unique.values())
    evidence = [r for (a,b),r in evidence.items() if a in rows and b in rows]
    barriers = []
    for r in policy['barriers']:
        ax, ay = to_map(r['map'], *r['a']); bx, by = to_map(r['map'], *r['b'])
        barriers.append('\t'.join(map(str, [r['map'], ax*100, ay*100, bx*100, by*100,
                                           r['cont'], *r['a'], *r['b']])))
    assert len(barriers) == 15, 'barrier verdict inventory changed'
    return ['\t'.join(rows[n] + [''] * max(0, 13-len(rows[n]))) for n in sorted(rows)], kept, sorted(evidence), barriers, sorted(labels)
