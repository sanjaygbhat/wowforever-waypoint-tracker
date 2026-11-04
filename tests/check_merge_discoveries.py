#!/usr/bin/env python3
"""Offline discovery importer regressions, including the real Lua reader."""
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from merge_discoveries import BLOCK, export_rows, merge, spots, validate

EMPTY = "-- preserved header\nWaypointTrackerData = {}\nWaypointTrackerData.forever = [==[\nWTL1\tcommunity\t1\n]==]\n"
MAPS = {1411, 1416, 1424, 1454, 2521}


def export(*rows):
    return "WTL1\tenUS\t1.1.1\n" + "\n".join("\t".join(row) for row in rows) + "\n"


def records(source):
    return {f[0] + (f[1] if f[0] != "M" else ""): f
            for _, f in export_rows(BLOCK.search(source)[1]) if f[0] != "C"}


class Discoveries(unittest.TestCase):
    def test_existing_fields_and_positions_win_and_new_fields_fill_gaps(self):
        first = export(["N", "1", "Original", "0", "60", "vendor", "1411:401,501,402,502", "H"],
                       ["Q", "2", "Quest", "", "U1", "", "1411:400,500"],
                       ["I", "3", "Item", "U1", "U1"])
        before, _ = merge(EMPTY, first, MAPS)
        # Historical near pairs remain byte-for-byte in their coordinate list.
        before = before.replace("1411:401,501", "1411:401,501,402,502")
        incoming = export(["N", "1", "Renamed", "1", "20", "repair,evil", "1411:409,509,450,550", "A", "Trainer"],
                          ["Q", "2", "Renamed", "30", "U9", "U1", "2521:1,1000", "Text", "item:Thing", "I3", "H"],
                          ["I", "3", "Renamed", "U2,U1", "U2"])
        result, report = merge(before, incoming, MAPS)
        f = records(result)
        self.assertEqual(f["N1"][2:], ["Original", "0", "60", "repair,vendor",
                         "1411:401,501,402,502,450,550", "H", "Trainer"])
        self.assertEqual(f["Q2"][2:], ["Quest", "30", "U1", "U1", "1411:400,500",
                         "Text", "item:Thing", "I3", "H"])
        self.assertEqual(f["I3"], ["I", "3", "Item", "U1,U2", "U1,U2"])
        self.assertEqual(report["counts"]["positions_merged_existing"], 1)
        self.assertTrue(result.startswith("-- preserved header\n"))
        self.assertEqual(merge(result, incoming, MAPS)[0], result)

    def test_invalid_records_rejected_whole_with_reasons(self):
        rows = [
            ["N", "2147483648", "Bad ID", "0", "1", "", ""],
            ["N", "0", "Zero", "0", "1", "", ""],
            ["N", "-1", "Negative", "0", "1", "", ""],
            ["N", "1.2", "Fractional", "0", "1", "", ""],
            ["N", "1", "Unknown map", "0", "1", "", "999999:100,100"],
            ["O", "2", "Overflow", "1411:1001,500"],
            ["O", "3", "Negative", "1411:-1,500"],
            ["O", "4", "Odd", "1411:1,2,3"],
            ["Q", "5", "Two areas", "", "", "", "1411:1,2,3,4"],
            ["Q", "6", "Bad ref", "", "U2147483648"],
            ["I", "7", "Bad seller", "", "O1"],
            ["O", "8", "]==] malicious", ""],
            ["O", "9", "]==|r] malicious", ""],
            ["N", "9", "Bad faction", "0", "1", "", "", "X"],
            ["C", "N", "10", "", ""],
            ["X", "11"],
        ]
        result, report = merge(EMPTY, export(*rows), MAPS)
        self.assertFalse(records(result))
        self.assertEqual(len(report["rejected"]), len(rows))
        self.assertIn("unknown uiMap", report["rejected"][4]["reason"])
        self.assertIn("coordinates", report["rejected"][5]["reason"])
        self.assertTrue(all(r["line"] >= 2 and r["reason"] for r in report["rejected"]))

    def test_dedup_and_limits_match_learn(self):
        coords = ",".join("%d,500" % (x * 20) for x in range(31))
        maps = set(range(1, 22))
        value = ";".join("%d:%s" % (m, coords if m == 1 else "0,1000") for m in sorted(maps))
        result, report = merge(EMPTY, export(["O", "1", "Many spots", value]), maps)
        points = spots(records(result)["O1"][3], maps)
        self.assertEqual(len(points), 20)
        self.assertEqual(len(points[1]), 30)
        self.assertEqual(report["counts"]["positions_limited"], 2)
        refs = ",".join("U%d" % n for n in range(1, 42))
        result, _ = merge(EMPTY, export(["I", "2", "Item", refs, refs]), MAPS)
        self.assertEqual(len(records(result)["I2"][3].split(",")), 40)
        self.assertEqual(len(records(result)["I2"][4].split(",")), 20)

    def test_no_guessed_quest_locations(self):
        result, _ = merge(EMPTY, export(["N", "1", "Giver", "0", "60", "", "1411:400,500"],
                                       ["Q", "2", "No area", "", "U1"]), MAPS)
        self.assertEqual(validate(records(result)["Q2"], MAPS)[6], "")
        result, _ = merge(result, export(["Q", "2", "No area", "", "", "", "2521:0,1000"]), MAPS)
        self.assertEqual(records(result)["Q2"][6], "2521:0,1000")

    def test_empty_position_columns_survive_reviewed_filter(self):
        from decimal import Decimal
        from filter_quest_locations import filtered
        body = export(["N", "2556", "Witherbark Headhunter", "1", "35", "", ""],
                      ["O", "2", "No observed location", ""])
        source = EMPTY.replace("WTL1\tcommunity\t1\n", body)
        result, _ = merge(source, export(["I", "3", "Item", "U2556"]), MAPS)
        self.assertEqual(records(result)["N2556"][6], "")
        self.assertEqual(records(result)["O2"][3], "")
        removals = {key: {(1411, Decimal(100), Decimal(200))} for key in ("N2556", "O2")}
        self.assertEqual(filtered(result, removals), (result, 0))
        self.assertEqual(merge(result, body, MAPS)[0], result)

    def test_first_observations_take_priority_at_limits(self):
        maps = set(range(1, 22))
        order = [21] + list(range(1, 21))
        value = ";".join("%d:0,0" % m for m in order)
        result, _ = merge(EMPTY, export(["O", "1", "Spots", value]), maps)
        kept = spots(records(result)["O1"][3], maps)
        self.assertIn(21, kept)
        self.assertNotIn(20, kept)
        refs = ["U%d" % n for n in range(41, 0, -1)]
        result, _ = merge(EMPTY, export(["I", "2", "Item", ",".join(refs), ""]), MAPS)
        self.assertNotIn("U1", records(result)["I2"][3].split(","))

    def test_total_entry_limit(self):
        incoming = export(*[["O", str(n), "Object", ""] for n in range(1, 20002)])
        result, report = merge(EMPTY, incoming, MAPS)
        self.assertEqual(len(records(result)), 20000)
        self.assertEqual(report["rejected"], [
            {"line": 20002, "entry": "O20001", "reason": "entry limit"}])

    def test_duplicate_records_and_stable_sort(self):
        body = export(["O", "20", "First", "1411:100,200"], ["O", "3", "Other", ""],
                      ["O", "20", "Second", "1411:200,300"])
        result, report = merge(EMPTY, body, MAPS)
        self.assertEqual(list(records(result)), ["O3", "O20"])
        self.assertEqual(records(result)["O20"], ["O", "20", "First", "1411:100,200,200,300"])
        self.assertEqual(report["counts"]["added_O"], 2)
        self.assertEqual(merge(result, body, MAPS)[0], result)
        with self.assertRaisesRegex(ValueError, "header missing"):
            merge(EMPTY, "not an export", MAPS)
        with self.assertRaisesRegex(ValueError, "duplicate existing"):
            merge(result.replace("O\t3\tOther", "O\t20\tOther"), body, MAPS)

    def test_corrections_replace_nearby_and_retain_limits(self):
        first = export(["C", "N", "1", "1411:100,200", "1411:400,500"],
                       ["C", "O", "2", "", "1411:500,600"])
        before, _ = merge(EMPTY, first, MAPS)
        incoming = export(["C", "N", "1", "1411:105,205", "1411:450,550"])
        result, _ = merge(before, incoming, MAPS)
        self.assertNotIn("1411:400,500", result)
        self.assertIn("C\tO\t2\t\t1411:500,600", result)
        self.assertEqual(merge(result, incoming, MAPS)[0], result)
        many = export(*[["C", "N", "3", "1411:%d,0" % (x * 100), ""] for x in range(6)])
        result, report = merge(EMPTY, many, MAPS)
        self.assertEqual(len(report["rejected"]), 1)
        self.assertEqual(report["rejected"][0]["reason"], "correction limit")

    def test_clean_text_and_optional_fields(self):
        f = validate(["N", "2147483647", "|cffffffffName|r |Hunit:1|hLink|h |Ttexture|t",
                      "1", "62", "vendor,unknown,repair", "", "A", "x" * 80], MAPS)
        self.assertEqual(f[2], "Name Link")
        self.assertEqual(f[5], "repair,vendor")
        self.assertEqual(len(f[8]), 60)
        self.assertEqual(len(validate(["Q", "1", "Quest"], MAPS)), 11)

    def test_real_lua_import_agrees(self):
        lua = os.environ.get("LUA51") or shutil.which("lua5.1")
        self.assertTrue(lua, "Lua 5.1 required (LUA51 or PATH)")
        before = export(["N", "1", "Old", "0", "60", "vendor", "1411:401,501", "H"],
                        ["Q", "2", "Quest", "", "U1"],
                        ["O", "5", "Boundary", "1411:289,500"])
        incoming = export(["N", "1", "New", "1", "20", "repair,unknown", "1411:409,509,450,550", "A", "Title"],
                          ["O", "3", "Object", "2521:0,1000"],
                          ["O", "5", "Boundary", "1411:290,500,294,500"],
                          ["Q", "2", "Other", "30", "U1", "O3", "2521:1,999", "Text", "item:Thing", "I4", "H"],
                          ["I", "4", "Item", "O3,U1", "U1"],
                          ["M", "1411:100,200,101,201"],
                          ["C", "N", "1", "1411:401,501", "1411:450,550"])
        source, _ = merge(EMPTY, before, MAPS)
        result, _ = merge(source, incoming, MAPS)
        script = '''package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
local function store() return { npcs={}, objects={}, quests={}, items={}, mailboxes={} } end
local a, b = store(), store()
ns.Learn.Import([====[%s]====], a, true)
ns.Learn.Import([====[%s]====], a, true)
ns.Learn.Import([====[%s]====], b, true)
local function canon(t)
    if type(t) ~= "table" then return type(t) .. ":" .. tostring(t) end
    local keys, out = {}, {}
    for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys, function(x,y) return tostring(x) < tostring(y) end)
    for _, k in ipairs(keys) do out[#out+1] = tostring(k) .. "=" .. canon(t[k]) end
    return "{" .. table.concat(out,";") .. "}"
end
assert(canon(a) == canon(b), "Python merge differs from Learn.Import: " .. canon(a) .. " / " .. canon(b))
assert(#M.errors == 0, table.concat(M.errors, "\\n"))
print("WTL1 Lua reader parity: passed")
''' % (before, incoming, BLOCK.search(result)[1])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "parity.lua"
            path.write_text(script)
            run = subprocess.run([lua, str(path)], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_issue10_replay_and_cli_check_are_read_only(self):
        with (ROOT / "tools/fixtures/travel/UiMap.csv").open() as handle:
            maps = {int(r["ID"]) for r in csv.DictReader(handle)}
        fixture = ROOT / "tools/fixtures/discoveries/issue-10.wtl"
        shipped = ROOT / "WaypointTracker_Data/Forever.lua"
        source = shipped.read_text()
        result, report = merge(source, fixture.read_text(), maps)
        self.assertEqual(result, source)
        self.assertEqual(report["rejected"], [])
        for kind, count in {"N": 315, "O": 21, "Q": 156, "I": 466, "M": 1}.items():
            self.assertEqual(report["counts"]["accepted_" + kind], count)
            self.assertEqual(report["counts"].get("added_" + kind, 0), 0)
        self.assertEqual(report["counts"].get("positions_added", 0), 0)
        # CLI writes no addon layer when checking a fresh merge.
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "Forever.lua"
            target.write_text(EMPTY)
            report_path = Path(tmp) / "report.json"
            run = subprocess.run([sys.executable, "-B", str(ROOT / "tools/merge_discoveries.py"),
                                  str(fixture), "--forever", str(target), "--check", "--report", str(report_path)],
                                 cwd=tmp, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(target.read_text(), EMPTY)
            self.assertEqual(json.loads(report_path.read_text())["rejected"], [])


if __name__ == "__main__":
    unittest.main()
