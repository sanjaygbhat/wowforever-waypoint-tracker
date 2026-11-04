#!/usr/bin/env python3
"""Offline regression checks for the v3 decoder and analytical evidence."""
import csv
import io
import json
import math
from pathlib import Path
import struct
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from audit_transport_v3 import TABLES, bits, catmull_length, chord_length, compare_csv, decode_wdc5
from verify_legs_casc import EvidenceUnavailable


def path_fixture(ids=(6,7)):
    count=len(ids)
    header=b'WDC5'+struct.pack('<I',5)+bytes(128)
    header+=struct.pack('<9I2H7I',count,4,8,2,0xAB30A45C,0xA303DE51,
                        min(ids),max(ids),0xffffffff,0,0,4,0,1,96,0,0,1)
    offset=356
    header+=struct.pack('<Q8I',0,offset,count,2,0,0,12+count*8,0,0)
    header+=b''.join(struct.pack('<hH',32,0) for _ in range(4))
    header+=b''.join(struct.pack('<HHIIIII',off,16,0,1,off,16,0) for off in (0,16,32,48))
    data=b''.join(struct.pack('<4H',tid,2,4,110) for tid in ids)+bytes(2)
    data+=struct.pack('<3I',count,2,2)+b''.join(struct.pack('<2I',2,i) for i in range(count))
    return header+data


class DecoderTests(unittest.TestCase):
    def test_fares_and_ids(self):
        r=decode_wdc5(path_fixture(),TABLES['TaxiPath'])
        self.assertEqual([x['ID'] for x in r],[6,7])
        self.assertEqual(r[0],dict(ID=6,FromTaxiNode=2,ToTaxiNode=4,Cost=110))

    def test_rejects_bad_binary(self):
        raw=path_fixture()
        invalid=[b'BAD!'+raw[4:],raw[:-1],raw[:156]+bytes(4)+raw[160:],path_fixture((6,6))]
        for r in invalid:
            with self.subTest(size=len(r)),self.assertRaises((EvidenceUnavailable,struct.error)):
                decode_wdc5(r,TABLES['TaxiPath'])

    def test_bit_bounds(self):
        self.assertEqual(bits(b'\xff\x01',7,3),3)
        with self.assertRaises(EvidenceUnavailable):bits(b'\0',7,2)

    def test_crosscheck_catches_wrong_cost(self):
        rows=decode_wdc5(path_fixture(),TABLES['TaxiPath'])
        csv=b'ID,FromTaxiNode,ToTaxiNode,Cost\n6,2,4,110\n7,2,4,110\n'
        self.assertEqual(compare_csv(rows,csv),8)
        with self.assertRaises(EvidenceUnavailable):compare_csv(rows,csv.replace(b'110',b'111',1))

    def test_curve_geometry(self):
        line=[(0,0,0),(3,4,0),(6,8,0)]
        self.assertAlmostEqual(chord_length(line),10)
        self.assertAlmostEqual(catmull_length(line),10)
        turn=[(0,0,0),(10,0,0),(10,10,0),(20,10,0)]
        self.assertGreater(catmull_length(turn),chord_length(turn))
        self.assertLess(abs(catmull_length(turn,128)-catmull_length(turn,64)),.01)

    def test_local_evidence_regressions(self):
        e=json.loads((ROOT/'docs/transport-v3-evidence.json').read_text())
        self.assertEqual(e['build']['Version!STRING:0'],'1.60.1.70338')
        self.assertEqual(e['table_rows'],dict(TaxiNodes=100,TaxiPath=328,TaxiPathNode=10778))
        self.assertEqual(sum(e['csv_cells_verified'].values()),121870)
        flights=e['flight_models']
        self.assertEqual(len(flights),290)
        self.assertTrue(all(r['fare_preserved'] and not r['measured'] for r in flights))
        h=next(r for r in flights if r['path_id']==316)
        self.assertAlmostEqual(h['chord_seconds_at30'],543.7772897348393)
        self.assertEqual(h['base_fare_copper'],0)
        isolated={r['ID']:r for r in e['uncertain_nodes']}
        self.assertEqual(isolated[3274]['outgoing'],[])
        self.assertEqual(isolated[3205]['incoming'],[])
        stop=next(s for s in e['transport_stops'] if s['path_id']==11391 and s['continent']==0)
        self.assertGreater(stop['nearest_endpoints'][0]['horizontal_yards'],800)
        self.assertEqual(stop['nearest_endpoints'][0]['id'],'DOCK_POWDERFUSE')
        s=json.loads((ROOT/'docs/transport-v3-client-services.json').read_text())
        self.assertEqual(s['animation_cache_cells_verified'],7112)
        self.assertEqual(s['tram_animation_candidates']['657020'][-1]['TimeIndex'],143333)


if __name__=='__main__':unittest.main()
