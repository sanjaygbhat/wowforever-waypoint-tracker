#!/usr/bin/env python3
"""Negative controls for the source-backed indoor anchor exception."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from validate_terrain_geometry import indoor_node_area


class IndoorProvenance(unittest.TestCase):
    def setUp(self):
        self.container = "easternkingdoms.elwynn_forest.stormwind_wizards_sanctum"
        self.raw = ["INNER", "entrance", self.container, "1453", "0.4936", "0.8693"]
        self.node = dict(id="INNER", kind="entrance", area=15, m=1453, x=49.36 / 100, y=86.93 / 100,
                         override="mapzeroth-indoor")
        self.areas = {14: "easternkingdoms.elwynn_forest", 15: self.container}

    def resolve(self, **kwargs):
        values = dict(n=self.node, surface=14, areas=self.areas, indoor={15},
                      source_nodes={"INNER": self.raw}, source_indoor={self.container})
        values.update(kwargs)
        return indoor_node_area(**values)

    def test_captured_node(self):
        self.assertEqual(self.resolve(), (15, None))

    def test_missing_flag_still_fails_area_gate(self):
        self.node["override"] = ""
        self.assertEqual(self.resolve(), (14, None))
        self.assertNotEqual(self.resolve()[0], self.node["area"])

    def test_rehoming_to_surface_cannot_hide_the_error(self):
        self.node.update(area=14, override="")
        self.assertIsNotNone(self.resolve()[1])

    def test_missing_source_node(self):
        self.assertIsNotNone(self.resolve(source_nodes={})[1])

    def test_source_indoor_marker_required(self):
        self.assertIsNotNone(self.resolve(source_indoor=set())[1])

    def test_shipped_indoor_marker_required(self):
        self.assertIsNotNone(self.resolve(indoor=set())[1])

    def test_outdoor_node_cannot_opt_in(self):
        self.raw[2] = self.areas[14]
        self.assertIsNotNone(self.resolve()[1])

    def test_changed_coordinates_map_or_kind(self):
        for key, value in (("x", .49361), ("y", .86931), ("m", 1429), ("kind", "taxi")):
            with self.subTest(key=key):
                self.assertIsNotNone(self.resolve(n={**self.node, key: value})[1])

    def test_unknown_flag(self):
        self.node["override"] = "skip-validation"
        self.assertIsNotNone(self.resolve()[1])

    def test_stale_override_after_survey(self):
        self.assertIsNotNone(self.resolve(surface=15)[1])

    def test_ordinary_node_keeps_surface_classification(self):
        self.node.update(id="OUTER", area=14, override="")
        self.assertEqual(self.resolve(), (14, None))


if __name__ == "__main__":
    unittest.main()
