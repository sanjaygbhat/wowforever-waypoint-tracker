#!/usr/bin/env python3
"""Adversarial tests for the new binary reader and terrain classifications."""
import hashlib
import math
from pathlib import Path
import struct
import sys
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from verify_legs_casc import EvidenceUnavailable, blte, chunks
from verify_legs_terrain import CHUNK, TILE, UNIT, TileTerrain, SavedLiteralParser, classify, candidate_path, plane, segment_points


def iff(tag, data):
    return tag[::-1].encode() + struct.pack('<I', len(data)) + data


def synthetic_tile(gradient=0, hole=False, water=False, center_peak=False):
    out=iff('MVER',struct.pack('<I',18))
    if water:
        headers=bytearray(3072)
        struct.pack_into('<3I',headers,0,3072,1,0)
        # full chunk constant liquid 3yd above the otherwise flat surface
        out+=iff('MH2O',bytes(headers)+struct.pack('<HHff4BII',2,2,3,3,0,0,8,8,0,0))
    for iy in range(16):
        for ix in range(16):
            header=bytearray(128)
            struct.pack_into('<3I',header,0,0x10000,ix,iy)
            if hole and ix==0 and iy==0:header[20]=1
            px,py=-iy*CHUNK,-ix*CHUNK
            struct.pack_into('<3f',header,104,px,py,0)
            heights=[]
            for row in range(17):
                for col in range(8 if row%2 else 9):
                    x=(col+(.5 if row%2 else 0))*UNIT
                    heights.append(gradient*(py-x)+(10 if center_peak and row==1 and col==0 else 0))
            out+=iff('MCNK',bytes(header)+iff('MCVT',struct.pack('<145f',*heights)))
    return out


class FakeWorld:
    def __init__(self, **overrides):self.overrides=overrides
    def sample(self,cont,x,y):
        s=dict(z=0,slope=0,hole=False,liquids=[],objects=[],unknown=False,
               terrain_fdid=1,chunk=[0,0],cell=[0,0],triangle=0)
        s.update(self.overrides)
        return s


def leg(a=(0,0),b=(100,0)):
    return dict(a=dict(id='a',cont=0,wx=a[0],wy=a[1]),b=dict(id='b',cont=0,wx=b[0],wy=b[1]))


class Tests(unittest.TestCase):
    def test_blte_checksums_and_modes(self):
        raw=b'evidence'*100;payload=b'Z'+zlib.compress(raw)
        data=b'BLTE'+struct.pack('>I',36)+b'\x0f\0\0\x01'+struct.pack('>II',len(payload),len(raw))+hashlib.md5(payload).digest()+payload
        self.assertEqual(blte(data),raw)
        corrupt=bytearray(data);corrupt[-1]^=1
        with self.assertRaises(EvidenceUnavailable):blte(bytes(corrupt))
        with self.assertRaises(EvidenceUnavailable):blte(b'BLTE'+b'\0'*4+b'Eunknown')
        self.assertEqual(blte(b'BLTE'+b'\0'*4+b'Nhello'),b'hello')

    def test_truncated_iff(self):
        with self.assertRaises(EvidenceUnavailable):list(chunks(b'REVM'+struct.pack('<I',10)+b'bad'))

    def test_analytic_height_slope_and_axes(self):
        terrain=TileTerrain(synthetic_tile(gradient=1),1,32,32)
        for x,y in [(-1,-2),(-58,-181),(-500,-499)]:
            s=terrain.sample(x,y)
            self.assertAlmostEqual(s['z'],y,places=3)
            self.assertAlmostEqual(s['slope'],45,places=3)
        with self.assertRaises(EvidenceUnavailable):TileTerrain(synthetic_tile(),1,31,32)

    def test_center_vertex_is_not_bilinear(self):
        t=TileTerrain(synthetic_tile(center_peak=True),1,32,32)
        self.assertAlmostEqual(t.sample(-UNIT/2,-UNIT/2)['z'],10,places=4)
        self.assertGreater(t.sample(-UNIT/2,-UNIT/2)['slope'],70)

    def test_holes_and_liquid_presence(self):
        t=TileTerrain(synthetic_tile(hole=True,water=True),1,32,32)
        s=t.sample(-1,-1)
        self.assertTrue(s['hole']);self.assertEqual(s['liquids'][0]['min_depth'],3)
        self.assertFalse(t.sample(-10,-10)['hole'])
        self.assertEqual(t.sample(-40,-40)['liquids'],[])

    def test_no_false_certification(self):
        self.assertEqual(classify(FakeWorld(),leg())['status'],'UNCERTAIN')
        self.assertEqual(classify(FakeWorld(slope=70),leg())['status'],'BLOCKED')
        for uncertain in [dict(slope=70,objects=[dict(type='bridge')]),dict(slope=70,hole=True),
                          dict(slope=70,unknown=True),dict(missing='encrypted'),dict(slope=51)]:
            self.assertEqual(classify(FakeWorld(**uncertain),leg())['status'],'UNCERTAIN')
        self.assertEqual(classify(FakeWorld(liquids=[dict(min_depth=3,max_depth=3)]),leg())['status'],'BLOCKED')

    def test_grid_triangle_slivers_are_sampled(self):
        pts=segment_points((.01,.02),(25,24.99))
        self.assertTrue(any(.49<x<.51 for _,x,y in segment_points((0,0),(1,1))))
        self.assertGreater(len(pts),math.ceil(math.hypot(25,25)/2))
        self.assertEqual(pts[0][0],0);self.assertEqual(pts[-1][0],1)

    def test_saved_data_is_never_executed(self):
        p=SavedLiteralParser('WaypointTrackerDB = { ["trails"] = { ["own"] = { [0] = { [123] = 65, }, }, }, }').parse()
        self.assertEqual(p['WaypointTrackerDB']['trails']['own'][0][123],65)
        with self.assertRaises(EvidenceUnavailable):SavedLiteralParser('WaypointTrackerDB = os.execute("touch evil")').parse()

    def test_terrain_path_avoids_a_steep_strip(self):
        class BarrierWorld(FakeWorld):
            def sample(self,c,x,y):
                s=super().sample(c,x,y)
                if 35<x<65 and -20<y<20:s['slope']=70
                return s
        p=candidate_path(BarrierWorld(),leg()['a'],leg()['b'],1000)
        self.assertEqual(p['status'],'UNCERTAIN')
        self.assertGreater(p['straight_ratio'],1)
        self.assertGreaterEqual(max(abs(y) for x,y in p['waypoints_world']),20)
        self.assertEqual(p['waypoints_world'][0],[0,0]);self.assertEqual(p['waypoints_world'][-1],[100,0])


if __name__=='__main__':unittest.main()
