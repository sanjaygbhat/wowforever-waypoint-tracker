"""Launch source comparison and boat endpoint/provenance regressions."""
import csv
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tools/fixtures/travel'


def block(name):
    text = (ROOT / 'WaypointTracker/TravelData.lua').read_text()
    return [r.split('\t') for r in re.search(r'\b' + name + r' = \[\[\n(.*?)\n\]\]', text, re.S)[1].splitlines() if r]


class LaunchTravel(unittest.TestCase):
    def test_launch_taxi_comparison(self):
        review = json.loads((FIXTURE / 'launch-review.json').read_text())
        raw = (FIXTURE / 'TaxiNodes-1.60.1.70755.csv').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), review['taxi_sha256'])
        old = {r['ID']: r for r in csv.DictReader((FIXTURE / 'TaxiNodes.csv').read_text().splitlines())}
        new = {r['ID']: r for r in csv.DictReader(raw.decode().splitlines())}
        self.assertEqual(len(new), 101)
        self.assertEqual(new.keys() - old.keys(), {'3361'})
        self.assertEqual({k: new[k] for k in old}, old)
        self.assertTrue(new['3361']['Name_lang'].startswith('Quest Path'))
        self.assertEqual(new['3361']['CharacterBitNumber'], '0')
        nodes = {r[0]: r for r in block('nodes')}
        self.assertNotIn('TAXI_3361', nodes)
        self.assertNotIn('TAXI_3260', nodes)  # Dalaran quest translocation, not an FM.
        for tid, zone, faction in [(559, 2482, ''), (3242, 2482, ''),
                                   (3203, 2548, 'Horde'), (3275, 2548, 'Alliance')]:
            self.assertEqual((int(nodes[f'TAXI_{tid}'][6]), nodes[f'TAXI_{tid}'][12]), (zone, faction))
        self.assertNotIn('TAXI_3274', nodes)  # Still no evidenced Horde Powderfuse paths.

    def test_corrected_stop_anchors_do_not_inherit_walk_proof(self):
        review = json.loads((FIXTURE / 'launch-review.json').read_text())
        policy = json.loads((FIXTURE / 'verified-routing.json').read_text())
        nodes = {r[0]: r for r in block('nodes')}
        records = {r['id']: r['values'] for r in policy['transport']}
        for old, new in review['stop_anchors'].items():
            self.assertEqual(nodes[old][1], 'pass')
            self.assertEqual(nodes[new][1], 'dock')
            stop = records[old]['exact_vehicle_stop']
            self.assertEqual(list(map(float, nodes[new][3:9])),
                             [stop['world_map'], *stop['world_xyz'][:2], stop['ui_map'], *stop['xy_percent']])
            self.assertFalse(any(new in r[:2] for r in block('walkEvidence')))
            self.assertFalse(any(new in r[:2] and r[2] == 'walk' for r in block('links')))
            self.assertFalse(any(old in r[:2] and r[2] == 'ship' for r in block('links')))
        self.assertIn(['DOCK_STEAMWHEEDLE_CLIENT_STOP', 'DOCK_POWDERFUSE_CLIENT_STOP',
                       'ship', 'unmeasured-traversal'], block('unmeasuredLinks'))

    def test_steamwheedle_ship_uses_reported_time_with_client_waits(self):
        # 1.3.1: reported 2 x 69 s aboard + 60 s wait replaces the 90 s placeholder
        # (docs/data-audit.md); the client path's own stop delays are that wait.
        links = {tuple(r[:3]): r for r in block('links')}
        ship = links['DOCK_STEAMWHEEDLE_CLIENT_STOP', 'DOCK_POWDERFUSE_CLIENT_STOP', 'ship']
        self.assertEqual(ship[3:7], ['198', '69', '1', ''])
        points = [p for p in csv.DictReader((FIXTURE / 'TaxiPathNode.csv').read_text().splitlines())
                  if p['PathID'] == '11391' and int(p['Delay'])]
        self.assertEqual(sorted((int(p['NodeIndex']), int(p['Delay'])) for p in points), [(5, 60), (23, 60)])
        self.assertEqual(int(ship[3]), 2 * int(ship[4]) + 60)

    def test_launch_boats_and_skyships_have_spline_evidence(self):
        policy = json.loads((FIXTURE / 'verified-routing.json').read_text())
        records = {r['id']: r['values'] for r in policy['transport']}
        points = list(csv.DictReader((FIXTURE / 'TaxiPathNode.csv').read_text().splitlines()))
        for nid in ['DOCK_STORMWIND', 'DOCK_AUBERDINE_STORMWIND', 'DOCK_MENETHIL',
                    'DOCK_SOUTHSHORE', 'DOCK_AUBERDINE_MENETHIL', 'DOCK_STEAMWHEEDLE',
                    'DOCK_POWDERFUSE', 'DOCK_VALANAAR', 'DOCK_SKYWATCHER',
                    'DOCK_ZEPHRAS_ALLIANCE', 'DOCK_DALARAN']:
            stop = records[nid]['exact_vehicle_stop']
            point = next(p for p in points if int(p['PathID']) == stop['path_id']
                         and int(p['NodeIndex']) == stop['node_index'])
            for i in range(3):
                self.assertAlmostEqual(float(point[f'Loc_{i}']), stop['world_xyz'][i], places=7)
            self.assertGreater(int(point['Delay']), 0)
        links = {tuple(r[:2]): r for r in block('links')}
        loop = ['DOCK_MENETHIL', 'DOCK_SOUTHSHORE', 'DOCK_AUBERDINE_MENETHIL']
        for a in loop:
            for b in loop:
                if a == b:
                    continue
                link = links[a, b]
                self.assertEqual((link[2], link[6], link[7]), ('ship', '1', ''))
                self.assertAlmostEqual(float(link[3]) - float(link[4]), 455 / 2, delta=0.5)
        self.assertEqual(links[loop[0], loop[1]][4], '135')
        self.assertEqual(links[loop[1], loop[0]][4], '200')
        self.assertEqual(links['DOCK_STORMWIND', 'DOCK_AUBERDINE_STORMWIND'][3:8], ['170', '55', '1', '', ''])


if __name__ == '__main__':
    unittest.main()
