"""Approved service eligibility, measured triggers, quest removals and stale inputs."""
import json
from pathlib import Path
import re
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from filter_quest_locations import filtered, removal_inputs


def block(text,name):
    return [line.split('\t') for line in re.search(r'\b'+name+r' = \[\[\n(.*?)\n\]\]',text,re.S)[1].splitlines() if line]


class VerifiedRouting(unittest.TestCase):
    def test_transport_fields(self):
        text=(ROOT/'WaypointTracker/TravelData.lua').read_text()
        rows=block(text,'links');nodes={r[0]:r for r in block(text,'nodes')}
        policy=json.loads((ROOT/'tools/fixtures/travel/verified-routing.json').read_text())
        self.assertEqual(sum(r['verdict']=='CORRECTED' for r in policy['transport']),35)
        self.assertEqual(sum(r['verdict']=='VERIFIED' for r in policy['transport']),28)
        for r in rows:
            if r[2] in ('ship','zeppelin','tram','transition'):self.assertEqual(r[7],'',r[:3])
            if r[2]=='portal':self.assertEqual((r[7],r[9]),('Alliance','Skyborne'))
            if r[2]=='taxi' and r[8]=='DRUID':self.assertEqual((r[6],r[11]),('1','1'))
        loop={'DOCK_MENETHIL','DOCK_SOUTHSHORE','DOCK_AUBERDINE_MENETHIL'}
        rides=[r for r in rows if r[0] in loop and r[1] in loop]
        self.assertEqual(len(rides),6);self.assertTrue(all(r[6]=='1' for r in rides))
        self.assertTrue(all(float(r[2])==10 for r in block(text,'teleports')))
        for r in policy['transport']:
            trigger=r['values'].get('exact_trigger')
            if trigger:
                n=nodes[r['id']]
                self.assertEqual(int(n[6]),trigger['ui_map'])
                for value,expected in zip(n[7:9],trigger['xy_percent']):self.assertAlmostEqual(float(value),expected,places=7)
        tram=next(r for r in rows if r[2]=='tram')
        self.assertEqual((tram[3],tram[4]),('120','58.633'))
        sky=next(r for r in rows if r[:2]==['DOCK_VALANAAR','DOCK_SKYWATCHER'])
        self.assertEqual(sky[3],'325')
        timing=block(text,'transportTiming')
        self.assertIn(['DOCK_SKYWATCHER','station-pause','60','client-measured'],timing)
        self.assertIn(['DOCK_VALANAAR','station-pause','30','client-measured'],timing)

    def test_positions_stay_removed_after_regeneration(self):
        for name,removals in removal_inputs().items():
            text=(ROOT/'WaypointTracker_Data'/name).read_text()
            result,count=filtered(text,removals)
            self.assertEqual(count,0,name);self.assertEqual(result,text,name)

    def test_position_filter_preserves_names_other_fields_and_confirmed_points(self):
        from decimal import Decimal
        text='N\t7\tConfirmed name\ttitle\tlevel\trank\t1416:229,595,231,604;1424:600,200\tH\n'
        result,count=filtered(text,{'N7':{(1416,Decimal(231),Decimal(604))}})
        self.assertEqual(count,1)
        self.assertEqual(result,'N\t7\tConfirmed name\ttitle\tlevel\trank\t1416:229,595;1424:600,200\tH\n')
        self.assertEqual(filtered(result,{'N7':{(1416,Decimal(231),Decimal(604))}}),(result,0))


if __name__=='__main__':unittest.main()
