"""Compiler integration invariants against the current generated data."""
import hashlib
import gzip
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def block(text, name):
    return [r.split('\t') for r in re.search(r'\b'+name+r' = \[\[\n(.*?)\n\]\]', text, re.S)[1].splitlines() if r]


class Tests(unittest.TestCase):
    def test_border_corrections_match_verified_chords_and_generated_positions(self):
        policy = json.loads((ROOT/'tools/fixtures/travel/verified-routing.json').read_text())
        raw = (ROOT/'tools/fixtures/travel/border-evidence.json.gz').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), policy['border_evidence_sha256'])
        proof = json.loads(gzip.decompress(raw))
        self.assertEqual(proof['build'], policy['build'])
        nodes = {r[0]:r for r in block((ROOT/'WaypointTracker/TravelData.lua').read_text(),'nodes')}
        for nid, position in policy['border_corrections'].items():
            self.assertEqual(nodes[nid][3:9], position)
        for record in proof['search']['records']:
            if record['verdict'] != 'VERIFIED-WALKABLE':
                continue
            self.assertEqual(len(record['segments']), len(record['points'])-1)
            for segment in record['segments']:
                self.assertEqual(segment['verdict'], 'VERIFIED-WALKABLE')
                for representation in ('world','native'):
                    self.assertEqual(segment[representation]['status'], 'PASSABLE')
                    self.assertLessEqual(segment[representation]['max_slope_deg'],45)
            replacement = [p for p in policy['replacements'] if p['replacement_id']=='link:'+record['id']]
            self.assertEqual(len(replacement),len(record['points']))
            for p,q in zip(replacement,record['points']):
                self.assertEqual([float(p[k]) for k in ('world_x','world_y','map_x','map_y')],
                                 [q[k] for k in ('wx','wy','x','y')])

    def test_reproducible_exact_consumer_representations(self):
        with tempfile.TemporaryDirectory(prefix='wt-terrainint-') as tmp:
            output = Path(tmp)/'TravelData.lua'
            subprocess.run(['python3','-B','tools/build_travel.py','tools/fixtures/travel',str(output)],cwd=ROOT,check=True,capture_output=True)
            self.assertEqual(output.read_bytes(),(ROOT/'WaypointTracker/TravelData.lua').read_bytes())
        text = (ROOT/'WaypointTracker/TravelData.lua').read_text()
        nodes = {r[0]:r for r in block(text,'nodes')}
        evidence = {(r[0],r[1]):r for r in block(text,'walkEvidence')}
        policy = json.loads((ROOT/'tools/fixtures/travel/verified-routing.json').read_text())
        active = {(r[0],r[1]) for r in block(text,'links') if r[2]=='walk'}
        self.assertEqual(block(text,'walkCandidates'),[])
        self.assertEqual(block(text,'walkCandidateEdges'),[])
        self.assertEqual(block(text,'ghostCorridors'),[])
        self.assertEqual(len(block(text,'barriers')),15)
        for a,b in active:
            row=evidence.get((a,b)) or evidence.get((b,a))
            self.assertIsNotNone(row,(a,b))
            self.assertIn(row[2],('TERRAIN_CLEAR','UNCERTAIN'))
            if row[2]=='UNCERTAIN':self.assertIn(a+'>'+b,policy['retain_unmeasured'])
        for (a,b),row in evidence.items():
            self.assertEqual(row[8:],nodes[a][3:9]+nodes[b][3:9])
            self.assertEqual(row[5],hashlib.sha256('\t'.join(row[8:]).encode()).hexdigest())
        for r in policy['walk']:
            if r['kind']=='link' and r['verdict']=='BLOCKED':
                self.assertNotIn((r['from_id'],r['to_id']),active)
                if r['from_id'] in nodes and r['to_id'] in nodes:
                    self.assertEqual(evidence[r['from_id'],r['to_id']][2],'TERRAIN_BLOCKED')
        # Every waypoint of the required exported objective route must survive.
        control=[p for p in policy['replacements'] if p['replacement_id']=='control:END_TO_END_TARREN_MILL_TO_557']
        positions={(int(r[3]),float(r[4]),float(r[5]),int(r[6]),float(r[7]),float(r[8])) for r in nodes.values()}
        for p in control:
            self.assertIn((int(p['continent']),float(p['world_x']),float(p['world_y']),int(p['map']),float(p['map_x']),float(p['map_y'])),positions)

    def test_changed_endpoint_fails_without_touching_output(self):
        with tempfile.TemporaryDirectory(prefix='wt-terrainint-') as tmp:
            extra=Path(tmp)/'extra.tsv';output=Path(tmp)/'output.lua'
            extra.write_text((ROOT/'tools/travel_extra.tsv').read_text().replace('1424\t38\t36\t','1424\t39\t36\t',1))
            output.write_text('sentinel')
            env=dict(os.environ,TRAVEL_EXTRA=str(extra))
            result=subprocess.run(['python3','-B','tools/build_travel.py','tools/fixtures/travel',str(output)],cwd=ROOT,env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('terrain endpoint changed',result.stderr)
            self.assertEqual(output.read_text(),'sentinel')

    def test_stale_consumer_checksum_fails(self):
        with tempfile.TemporaryDirectory(prefix='wt-terrainint-') as tmp:
            consumer=json.loads((ROOT/'docs/terrain-consumer-final.json').read_text());consumer['input_sha256']='stale'
            path=Path(tmp)/'consumer.json';path.write_text(json.dumps(consumer))
            result=subprocess.run(['python3','-B','tools/build_travel.py','tools/fixtures/travel',str(Path(tmp)/'output.lua')],cwd=ROOT,
                env=dict(os.environ,TRAVEL_TERRAIN_EVIDENCE=str(path)),capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertIn('stale terrain evidence',result.stderr)


if __name__=='__main__':unittest.main()
