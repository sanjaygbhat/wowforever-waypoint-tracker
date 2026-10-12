#!/usr/bin/env python3
"""Meaningful regression controls for precision, strict cliffs and path validation."""
import importlib.util
import math
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from verify_legs_calibrated import AdaptivePaths, cell_control, checked, key, worldpoint

class Surface:
    def sample(self, cont, x, y):
        return dict(z=0, slope=self.slope(x,y), hole=False, liquids=[], objects=[], unknown=False,
                    terrain_fdid=1, chunk=[0,0], cell=[0,0], triangle=0)
    def slope(self,x,y): return 0

class Quantized(Surface):
    def slope(self,x,y): return 75 if abs(y-10)<1 else 0

class Wall(Surface):
    def slope(self,x,y): return 80 if 75<=x<=125 and -800<=y<=800 else 0

class Tests(unittest.TestCase):
    def test_observation_precision_does_not_relax_cliffs(self):
        w=Quantized();a=dict(cont=0,wx=10,wy=10);b=dict(cont=0,wx=30,wy=10)
        self.assertEqual(checked(w,a,b)['status'],'BLOCKED')
        r=cell_control(w,0,key(0,0),key(1,0))
        self.assertEqual(r['center_result']['status'],'BLOCKED')
        self.assertEqual(r['status'],'UNCERTAIN')
        self.assertIn('compatible_chord',r)
        self.assertEqual(checked(w,a,b)['status'],'BLOCKED')
    def test_static_clear_is_separate_from_object_floor(self):
        w=Surface();a=dict(cont=0,wx=0,wy=0);b=dict(cont=0,wx=20,wy=0)
        self.assertEqual(checked(w,a,b)['status'],'PASSABLE')
        class Bridge(Surface):
            def sample(self,cont,x,y):
                r=super().sample(cont,x,y);r.update(slope=85,objects=[dict(type='WMO',fdid=2)])
                return r
        self.assertEqual(checked(Bridge(),a,b)['status'],'UNCERTAIN')
        class Missing(Surface):
            def sample(self,cont,x,y): return dict(missing='no tile')
        self.assertEqual(checked(Missing(),a,b)['status'],'UNCERTAIN')
    def test_adaptive_search_leaves_600_yard_corridor_and_validates(self):
        maps={1:dict(MapID='0',Region_0='-1000',Region_1='-1000',Region_3='1000',Region_4='1000')}
        w=Wall();p=AdaptivePaths(w,maps,[])
        a=dict(id='a',cont=0,map=1,wx=0,wy=0);b=dict(id='b',cont=0,map=1,wx=200,wy=0)
        self.assertEqual(checked(w,a,b)['status'],'BLOCKED')
        r=p.route(a,b)
        self.assertEqual(r['status'],'PASSABLE')
        self.assertTrue(any(t['envelope_yards'] is None for t in r['attempts']))
        self.assertTrue(any(abs(y)>800 for x,y in r['waypoints_world']))
        points=[worldpoint(maps,*q) for q in r['waypoints_map']]
        for a,b in zip(points,points[1:]): self.assertEqual(checked(w,a,b)['status'],'PASSABLE')
    def test_blocked_endpoint_is_not_teleported_to_nearby_polygon(self):
        maps={1:dict(MapID='0',Region_0='-100',Region_1='-100',Region_3='100',Region_4='100')}
        a=dict(id='a',cont=0,map=1,wx=10,wy=10);b=dict(id='b',cont=0,map=1,wx=80,wy=50)
        r=AdaptivePaths(Quantized(),maps,[]).route(a,b)
        self.assertNotIn('waypoints_world',r)
        self.assertIn('endpoint',r['reason'])

if __name__=='__main__': unittest.main()
