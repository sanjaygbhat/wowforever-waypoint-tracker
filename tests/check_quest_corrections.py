#!/usr/bin/env python3
"""Check the reviewed curation patch without changing the working tree."""
import csv
from pathlib import Path
import re
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from stage_quest_corrections import corrected, FIELDS
import json


def records(text):
    body = re.search(r"WaypointTrackerData\.curated\s*=\s*\[==\[(.*?)\]==\]", text, re.S)[1]
    out = {}
    for line in body.splitlines():
        fields = line.split("\t")
        if fields[0] in ("N", "O", "Q", "I"):
            out[fields[0] + fields[1]] = fields
    return out


class QuestCorrections(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "WaypointTracker_Data/Curated.lua").read_text()
        with (ROOT / "tools/corrections_quests.tsv").open(newline="") as handle:
            cls.corrections = list(csv.DictReader(handle, delimiter="\t"))
        live = records(cls.source)
        applied = all(live[c["record"]][FIELDS[c["record"][0]][c["field"]]] == c["value"]
                      for c in cls.corrections if c["field"] != "record")
        if applied:
            # Reconstruct just the reviewed input fields in memory. This tests
            # the compare-and-set patch after publication without weakening
            # stale-input checks or changing the applied data on disk.
            match = re.search(r"WaypointTrackerData\.curated\s*=\s*\[==\[(.*?)\]==\]", cls.source, re.S)
            lines = match[1].splitlines()
            for c in cls.corrections:
                key = c["record"]
                if c["field"] == "record" and key not in live:
                    # Published named identities may live in ReferenceData or
                    # the recovery overlay, with positions verified separately
                    # by the normal provenance gates.
                    published = cls.source + (ROOT / "WaypointTracker_Data/ReferenceData.lua").read_text()
                    names = re.findall(r"(?m)^O\t" + key[1:] + r"\t([^\t\n]+)\t", published)
                    assert names and all(name == json.loads(c["value"])[2] for name in names), key
                    continue
                ix = next(i for i, line in enumerate(lines)
                          if line.split("\t")[:2] == [key[0], key[1:]])
                if c["field"] == "record":
                    assert lines[ix].split("\t") == json.loads(c["value"]), key
                    lines.pop(ix)
                else:
                    fields = lines[ix].split("\t")
                    fields[FIELDS[key[0]][c["field"]]] = c["expected"]
                    lines[ix] = "\t".join(fields)
            cls.source = cls.source[:match.start(1)] + "\n".join(lines) + "\n" + cls.source[match.end(1):]
        cls.result, cls.additions = corrected(cls.source, cls.corrections)
        cls.before, cls.after = records(cls.source), records(cls.result)
        if applied:
            assert {k:v for k,v in cls.after.items() if k not in cls.additions} == {
                k:v for k,v in live.items() if k not in cls.additions}, 'reapplied fields differ from published records'

    def test_only_reviewed_fields_change(self):
        fields = {"spots": {"N": 6, "O": 3}, "fac": {"N": 7}, "giver": {"Q": 4}}
        expected = {}
        for c in self.corrections:
            if c["field"] != "record":
                expected.setdefault(c["record"], set()).add(fields[c["field"]][c["record"][0]])
        for key, old in self.before.items():
            changed = {i for i, (a, b) in enumerate(zip(old, self.after[key])) if a != b}
            self.assertEqual(changed, expected.get(key, set()), key)
            self.assertEqual(len(old), len(self.after[key]), key)

    def test_quest_endpoints_remain_distinct(self):
        self.assertEqual(self.after["Q140"][4], "O34")
        self.assertEqual(self.after["Q2781"][4], "O150075,O142122")
        self.assertEqual(self.after["Q2875"][4], "O150075,O142122")
        self.assertEqual(self.after["Q1067"][4], "U2216")
        self.assertEqual(self.after["N313"][6], "1429:652,698")
        self.assertEqual(self.after["N1442"][6], "")
        self.assertEqual(self.after["N15197"][6], "1420:556,699")

    def test_source_supported_forever_changes_survive(self):
        self.assertEqual(self.before["N5891"], self.after["N5891"])
        self.assertEqual(self.before["N6568"], self.after["N6568"])

    def test_new_objects_have_no_fabricated_positions(self):
        self.assertEqual(len(self.additions), 40)
        for key in self.additions:
            self.assertEqual(self.after[key][0], "O")
            self.assertTrue(self.after[key][2])
            self.assertEqual(self.after[key][3], "")
        self.assertNotIn("O100000000", self.additions)
        self.assertNotIn("O100000001", self.additions)

    def test_stale_input_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Stale expected value"):
            corrected(self.source.replace("1429:652,698;1433:741,467", "1429:650,690"), self.corrections)
        with self.assertRaises(ValueError):
            corrected(self.result, self.corrections)


if __name__ == "__main__":
    unittest.main()
