#!/usr/bin/env python3
"""Integrity and non-certification checks for the final generated artifacts."""
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from verify_legs_terrain import tsv_block
from validate_terrain_detour_export import consumer_point

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

class Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.analysis=json.loads((ROOT/'docs/terrain-calibrated-final.json').read_text())
        cls.consumer=json.loads((ROOT/'docs/terrain-consumer-final.json').read_text())
        cls.rows=[r.split('\t') for r in (ROOT/'tools/terrain_detours_final.tsv').read_text().splitlines()
                  if r and not r.startswith('#')]
    def test_all_original_legs_and_probes_present(self):
        r=self.analysis['records'];self.assertEqual(len(r),165)
        self.assertEqual(len({x['id'] for x in r}),165)
        self.assertEqual(Counter(x['status'] for x in r if x['kind']=='review-leg'),Counter(BLOCKED=131,UNCERTAIN=6))
        self.assertEqual(sum(x['kind']=='barrier-crossing' for x in r),22)
    def test_calibration_does_not_claim_unavailable_ground_truth(self):
        c=self.analysis['calibration'];s=c['summary']
        self.assertFalse(s['physical_slope_limit_empirically_calibrated'])
        self.assertEqual(s['exact_ground_controls_available'],0)
        self.assertEqual(s['naive_center_blocked'],12)
        self.assertEqual(s['own_reciprocal_undirected_transitions'],475)
        self.assertEqual(s['negative_controls'],dict(BLOCKED=2))
        self.assertEqual(c['route_log_diagnostics'], [])
        self.assertNotIn('saved_snapshots', c)
        self.assertNotIn('character_snapshots', c)
    def test_input_output_and_executed_tool_checksums(self):
        c=self.consumer
        self.assertEqual(c['input_sha256'],digest(ROOT/'docs/terrain-calibrated-final.json'))
        self.assertEqual(c['output_tsv_sha256'],digest(ROOT/'tools/terrain_detours_final.tsv'))
        self.assertEqual(c['tool_sha256'],digest(ROOT/'tools/validate_terrain_detour_export.py'))
        for p in ['tools/verify_legs_calibrated.py','tools/verify_legs_casc.py','tools/verify_legs_terrain.py']:
            self.assertEqual(self.analysis['read_input_sha256'][p],digest(ROOT/p))
    def test_every_active_link_has_both_coordinate_proofs_and_no_uncertain_activation(self):
        nodes={r[1]:r for r in self.rows if r[0]=='node'}
        links={(r[1],r[2]) for r in self.rows if r[0]=='link'};expected=set()
        self.assertEqual(len(nodes),417);self.assertEqual(len(links),314)
        for chain in self.consumer['chains']:
            self.assertFalse(chain['full_chain_static_clear'])
            ids=chain['node_ids']
            for i,s in enumerate(chain['segment_results']):
                self.assertNotEqual(s['status'],'BLOCKED')
                if s['status']=='PASSABLE':
                    self.assertEqual(s['native']['status'],'PASSABLE');self.assertEqual(s['fallback']['status'],'PASSABLE')
                    expected.add((ids[i],ids[i+1]))
                    for j in [i,i+1]:
                        if 0<j<len(ids)-1:
                            row=nodes[ids[j]];mid,x,y=chain['map_points'][j]
                            self.assertEqual((int(row[4]),float(row[5]),float(row[6])),(mid,x,y))
                else:self.assertNotIn((ids[i],ids[i+1]),links)
        self.assertEqual(links,expected)
    def test_actual_builder_preview_contains_expected_rows_without_rounding_drift(self):
        p=ROOT/'WaypointTracker/TravelData.lua'
        text=p.read_text();nodes={r[0]:r for r in tsv_block(text,'nodes')}
        links={(r[0],r[1]) for r in tsv_block(text,'links') if r[2]=='walk'}
        with (ROOT/'tools/fixtures/travel/UiMapAssignment.csv').open() as stream:
            maps={int(r['UiMapID']):r for r in csv.DictReader(stream) if r['UiMin_0']=='0' and r['UiMax_0']=='1'}
        policy=json.loads((ROOT/'tools/fixtures/travel/verified-routing.json').read_text())
        verdicts={(r['kind'],r['id']):r['verdict'] for r in policy['walk']}
        for r in self.rows:
            if r[0]=='node':
                if r[1] not in nodes:
                    self.assertFalse(any(v['kind']=='link' and v['verdict']=='VERIFIED-WALKABLE'
                        and r[1] in (v['from_id'],v['to_id']) for v in policy['walk']))
                    continue
                n=nodes[r[1]];self.assertEqual((int(n[6]),float(n[7]),float(n[8])),(int(r[4]),float(r[5]),float(r[6])))
                fallback=consumer_point(maps,int(r[4]),float(r[5]),float(r[6]))['fallback_point']
                self.assertEqual((float(n[4]),float(n[5])),(fallback['wx'],fallback['wy']))
            elif r[0]=='link':
                if verdicts['link',r[1]+'>'+r[2]]=='VERIFIED-WALKABLE':self.assertIn((r[1],r[2]),links)
                else:self.assertNotIn((r[1],r[2]),links)

if __name__=='__main__':unittest.main()
