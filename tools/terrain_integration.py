"""Compile frozen terrain evidence without promoting unresolved collision gaps."""
import hashlib
import json
from pathlib import Path


def compile_terrain(root, nodes, node_lines, cidx, to_world, fmt, evidence_path=None):
    consumer_path = Path(evidence_path or root / 'docs/terrain-consumer-final.json')
    consumer = json.loads(consumer_path.read_text())
    chord_path = root / 'docs/terrain-calibrated-final.json'
    chord = json.loads(chord_path.read_text())
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    if (consumer['schema'] != 'wt-terrain-consumer-check-v1'
            or chord['schema'] != 'wt-terrain-calibrated-v2'
            or chord['build']['version'] != '1.60.1.70338'
            or consumer['input_sha256'] != sha(chord_path)
            or consumer['output_tsv_sha256'] != sha(root / 'tools/terrain_detours_final.tsv')):
        raise ValueError('stale terrain evidence/build/TSV')
    for name in ('Map.csv', 'UiMapAssignment.csv'):
        rel = 'tools/fixtures/travel/' + name
        if sha(root / rel) != chord['original_coordinate_input_sha256'][rel]:
            raise ValueError('terrain transform fixture changed: ' + name)
    rows = {s.split('\t')[0]: s.split('\t') for s in node_lines}
    for record in chord['records']:
        if record['kind'] not in ('review-leg', 'road-approach'):
            continue
        for p in (record['a'], record['b']):
            n = rows.get(p['id'])
            if not n or int(n[6]) != p['map'] or abs(float(n[7])-p['x']) > .011 or abs(float(n[8])-p['y']) > .011:
                raise ValueError('terrain endpoint changed: ' + p['id'])
            if int(n[3]) != p['cont'] or abs(float(n[4])-p['wx']) > .11 or abs(float(n[5])-p['wy']) > .11:
                raise ValueError('terrain fallback endpoint changed: ' + p['id'])
    pending, edges, evidence = [], [], {}
    # Preserve the shipped evidence identity after removing private diagnostics.
    source = consumer.get('snapshot_source_sha256') or sha(consumer_path)

    def emit(a, b, state, chain=''):
        # Both consumed representations are part of the persistence identity.
        positions = rows[a][3:9] + rows[b][3:9]
        fingerprint = hashlib.sha256('\t'.join(positions).encode()).hexdigest()
        evidence[(a, b)] = '\t'.join([a, b, state, 'terrain-static,unverified-collision',
            chord['build']['version'], fingerprint, source, chain] + positions)

    for chain in consumer['chains']:
        ids = chain['node_ids']
        container = nodes[ids[0]]['container']
        for nid, (m, x, y) in zip(ids, chain['map_points']):
            if nid in rows:
                if int(rows[nid][6]) != m or abs(float(rows[nid][7])-x) > .011 or abs(float(rows[nid][8])-y) > .011:
                    raise ValueError('terrain consumed position changed: ' + nid)
                continue
            cont, wx, wy = to_world(m, x/100, y/100)
            row = [nid, 'pass', str(cidx[container]), str(cont), fmt(wx), fmt(wy), str(m), fmt(x, 2), fmt(y, 2)]
            rows[nid] = row
            pending.append('\t'.join(row))
        for i, segment in enumerate(chain['segment_results']):
            a, b = ids[i:i+2]
            state = 'TERRAIN_CLEAR' if segment['status'] == 'PASSABLE' else 'UNCERTAIN'
            if state == 'TERRAIN_CLEAR' and (segment['native']['status'] != 'PASSABLE' or segment['fallback']['status'] != 'PASSABLE'):
                raise ValueError('terrain native/fallback mismatch')
            emit(a, b, state, chain['chain'])
            if state == 'UNCERTAIN':
                edges.append(a + '\t' + b)
    for record in chord['records']:
        if record['kind'] in ('review-leg', 'road-approach'):
            emit(record['a']['id'], record['b']['id'], 'TERRAIN_BLOCKED' if record['status'] == 'BLOCKED' else 'UNCERTAIN')
    return sorted(evidence.values()), pending, edges
