"""Launch transport corrections layered after the frozen terrain compilation.

Never move an endpoint carrying old walking proof. Keep that point as a pass,
and route the boat between separate client stop anchors with unmeasured access.
"""
import json


def apply_launch(root, node_lines, links, unmeasured, transport_evidence):
    fixture = root / 'tools/fixtures/travel'
    review = json.loads((fixture / 'launch-review.json').read_text())
    policy = json.loads((fixture / 'verified-routing.json').read_text())
    records = {r['id']: r for r in policy['transport']}
    rows = {r.split('\t')[0]: r.split('\t') for r in node_lines}
    aliases = review['stop_anchors']
    for old, new in aliases.items():
        values = records[old]['values']
        assert values['keep_authored_position_as_boarding'] is False
        stop = values['exact_vehicle_stop']
        original = rows[old]
        anchor = original[:]
        anchor[0] = new
        anchor[3:9] = [str(stop['world_map']), *map(str, stop['world_xyz'][:2]),
                       str(stop['ui_map']), *map(str, stop['xy_percent'])]
        rows[new] = anchor
        original[1] = 'pass'  # Preserve every terrain fingerprint at its old coordinates.
        transport_evidence.append(new + '\tCORRECTED\tvehicle-stop-verified,access-unmeasured')
    for link in links:
        if link[2] != 'ship' or not any(n in aliases for n in link[:2]):
            continue
        link[:2] = [aliases.get(n, n) for n in link[:2]]
        unmeasured.append('\t'.join(link[:3] + ['unmeasured-traversal']))
    # Dalaran has no own UiMap and no recorded inn. Use its existing anchors
    # for the same estimated guard exposure model used by faction towns.
    hostile = []
    for nid, faction in sorted(review['hostile_approaches'].items()):
        assert nid in rows and rows[nid][10] == '279'
        hostile.append(nid + '\t' + faction)
    return ['\t'.join(rows[n]) for n in sorted(rows)], hostile
