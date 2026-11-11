"""Teleport reagents and teleport items come from the pinned client tables.

The generated teleports/abilities blocks must match the client's SpellReagents,
ItemEffect and ItemSparse rows, and tools/build_travel.py must refuse an item
row the client's own spell text doesn't support.
"""
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tools/fixtures/travel'
BUILD = '1.60.1.70862'


def block(name, path=ROOT / 'WaypointTracker/TravelData.lua'):
    text = Path(path).read_text()
    return [r.split('\t') for r in re.search(r'\b' + name + r' = \[\[\n(.*?)\n\]\]', text, re.S)[1].splitlines() if r]


def table(name):
    return list(csv.DictReader((FIXTURE / ('%s-%s-enUS.csv' % (name, BUILD))).read_text().splitlines()))


def build(items_text=None):
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ)
        if items_text is not None:
            items = Path(tmp) / 'items.tsv'
            items.write_text(items_text)
            env['TRAVEL_ITEMS'] = str(items)
        out = Path(tmp) / 'TravelData.lua'
        r = subprocess.run(['python3', '-B', 'tools/build_travel.py', 'tools/fixtures/travel', str(out)],
                           cwd=ROOT, env=env, capture_output=True, text=True)
        return r, (out.read_bytes() if out.exists() else None)


class TravelItems(unittest.TestCase):
    def test_fixtures_are_pinned(self):
        manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
        for name in ('SpellReagents', 'SpellMisc', 'SpellCastTimes', 'SpellName', 'Spell', 'SpellEffect',
                     'ItemXItemEffect', 'ItemEffect', 'ItemSparse', 'PlayerCondition'):
            rel = 'travel/%s-%s-enUS.csv' % (name, BUILD)
            raw = (ROOT / 'tools/fixtures' / rel).read_bytes()
            self.assertEqual(manifest[rel]['sha256'], hashlib.sha256(raw).hexdigest(), rel)
            self.assertIn('build=' + BUILD, manifest[rel]['source'])

    def test_generated_data_is_current(self):
        result, data = build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(data, (ROOT / 'WaypointTracker/TravelData.lua').read_bytes())

    def test_teleport_reagents_match_the_client(self):
        reagents = {r['SpellID']: (r['Reagent_0'], r['ReagentCount_0']) for r in table('SpellReagents')}
        rows = block('teleports')
        self.assertEqual(len(rows), 7)
        for spell, node, cast, item, count in rows:
            self.assertEqual(cast, '10')
            self.assertEqual((item, count), reagents.get(spell, ('', '')), spell)
        self.assertEqual({r[0] for r in rows if r[3] == '17031'}, {'3561', '3562', '3563', '3565', '3566', '3567'})
        self.assertNotIn('18960', reagents)  # Teleport: Moonglade
        self.assertNotIn('556', reagents)    # Astral Recall
        self.assertNotIn('8690', reagents)   # Hearthstone

    def test_items_match_the_client(self):
        sparse = {r['ID']: r for r in table('ItemSparse')}
        effects = {r['ID']: r for r in table('ItemEffect')}
        uses = {r['ItemID']: effects[r['ItemEffectID']] for r in table('ItemXItemEffect')}
        rows = [r for r in block('abilities') if r[0] == 'item']
        self.assertEqual([(r[1], r[2], r[5]) for r in rows], [
            ('18984', 'INN_11118', ''), ('260820', 'INN_11118', ''), ('18986', 'INN_7733', ''),
            ('260819', 'INN_7733', ''), ('282006', 'CITY_ORGRIMMAR', 'Horde'), ('282006', 'CITY_STORMWIND', 'Alliance')])
        for r in rows:
            s, e = sparse[r[1]], uses[r[1]]
            self.assertEqual(r[4], str(max(int(e['CoolDownMSec']), 0) // 1000), r[1])
            self.assertEqual(r[6] == '1', s['InventoryType'] != '0', r[1])
            self.assertEqual(r[7] == '1', int(e['Charges']) > 0, r[1])
            self.assertEqual(r[8:12], [v if v != '0' else '' for v in
                                       (s['RequiredAbility'], s['RequiredSkill'], s['RequiredSkillRank'], s['RequiredLevel'])], r[1])
        self.assertEqual({r[1] for r in rows if r[12] == '1'}, {'18984', '260820', '18986', '260819'})

    def test_build_refuses_unsupported_items(self):
        result, _ = build('18984\ttown:gadgetzan\t\tGadgetzan\tmisfire\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("doesn't name Gadgetzan", result.stderr)
        result, _ = build('282006\tCITY_ORGRIMMAR\tAlliance\tOrgrimmar\t\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("doesn't name Orgrimmar", result.stderr)
        result, _ = build('17031\tCITY_STORMWIND\t\tStormwind\t\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('expected one on-use effect', result.stderr)
        result, _ = build('18984\tNO_SUCH_NODE\t\tEverlook\t\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not a network node', result.stderr)


if __name__ == '__main__':
    unittest.main()
