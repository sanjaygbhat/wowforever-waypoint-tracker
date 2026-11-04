#!/usr/bin/env python3
"""The current builder rounds map percentages and fallback world independently."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from validate_terrain_detour_export import consumer_point, projected
from verify_legs_calibrated import worldpoint

class Tests(unittest.TestCase):
    def test_builder_rounding_has_two_distinct_coordinate_representations(self):
        maps={1:dict(MapID='0',Region_0='0',Region_1='0',Region_3='5000',Region_4='5000')}
        p=consumer_point(maps,1,12.3456789,45.6789123)
        self.assertEqual(p['map_row'],[1,12.35,45.68])
        self.assertEqual(p['map_point']['wx'],2716.0)
        self.assertEqual(p['fallback_point']['wx'],2716.1)
        self.assertAlmostEqual(p['map_point']['wy'],4382.5)
        self.assertEqual(p['fallback_point']['wy'],4382.7)
    def test_projection_uses_neighbor_map_without_clamping_world_position(self):
        maps={1411:dict(MapID='1',Region_0='0',Region_1='0',Region_3='100',Region_4='100'),
              1412:dict(MapID='1',Region_0='100',Region_1='0',Region_3='200',Region_4='100')}
        m,x,y=projected(maps,1411,150,50)
        self.assertEqual(m,1412)
        p=worldpoint(maps,m,x,y)
        self.assertEqual((p['wx'],p['wy']),(150,50))

if __name__=='__main__':unittest.main()
