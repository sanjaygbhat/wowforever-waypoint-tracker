#!/usr/bin/env python3
"""Offline trainer evidence, checksum, determinism and malformed-input gates."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_trainers as build


class Trainers(unittest.TestCase):
    def test_generated_current(self):
        self.assertEqual(build.OUTPUT.read_text(), build.generate(build.read_rows()))

    def test_fixture_pinned(self):
        manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
        self.assertEqual(manifest['trainers/trainers.tsv']['sha256'], hashlib.sha256(build.FIXTURE.read_bytes()).hexdigest())

    def test_deterministic_and_compact(self):
        rows = build.read_rows()
        self.assertEqual(build.generate(rows), build.generate(list(reversed(rows))))
        # The expanded roster plus fallback names/coordinates stays below 8 KiB.
        self.assertLess(len(build.generate(rows).encode()), 8192)
        self.assertNotIn('trainer_pet', build.generate(rows))
        self.assertNotIn('trainer_demon', build.generate(rows))
        self.assertNotIn('trainer_portal', build.generate(rows))
        self.assertTrue(any(not row['faction'] for row in rows))

    def invalid(self, mutate, message):
        rows = copy.deepcopy(build.read_rows())
        mutate(rows)
        import csv
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'trainers.tsv'
            with path.open('w', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=rows[0].keys(), delimiter='\t')
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaisesRegex(ValueError, message):
                build.read_rows(path)

    def test_missing_evidence(self):
        self.invalid(lambda rows: rows[0].update(evidence=''), 'missing source/evidence')
        self.invalid(lambda rows: rows[0].update(source=''), 'missing source/evidence')

    def test_unknown_kind_subkind(self):
        self.invalid(lambda rows: rows[0].update(kind='unknown'), 'unknown kind/subkind')
        self.invalid(lambda rows: rows[0].update(subkind='unknown'), 'unknown kind/subkind')

    def test_recipe_only_profession_rejected(self):
        def mutate(rows):
            row = next(r for r in rows if r['kind'] == 'profession' and build.SOURCE not in r['source'])
            row.update(evidence='NPC under prof(171); teaches recipe(123)', rank='')
        self.invalid(mutate, 'profession lacks trainer evidence')

    def test_structured_profession_evidence(self):
        cases = [
            ('NPC under prof(171); teaches recipe(123); highest explicit profession rank=', ''),
            ('NPC under prof(171); teaches recipe(123); no highest explicit profession rank=present', ''),
            ('observed title=Pet Trainer; service=trainer', ''),
            ('NPC under prof(171); teaches recipe(123); highest explicit profession rank=master', ''),
            ('NPC under prof(164); teaches recipe(123); highest explicit profession rank=expert', 'expert'),
            ('explicit NPC title <Blacksmithing Trainer>', ''),
            ('observed title=Blacksmith; service=trainer', ''),
            ('NPC under prof(171); teaches recipe(123); highest explicit profession rank=expert', 'artisan'),
        ]
        for evidence, rank in cases:
            with self.subTest(evidence=evidence, rank=rank):
                def mutate(rows):
                    row = next(r for r in rows if r['kind'] == 'profession' and build.SOURCE not in r['source'])
                    row.update(subkind='alchemy', rank=rank, evidence=evidence)
                self.invalid(mutate, 'profession lacks trainer evidence')

    def test_pattern_evidence_matches_profession(self):
        data = json.loads(build.EVIDENCE.read_text())
        title = next(t for t, p in data['patterns'].items() if p['basis'] == 'prior fixture')
        for evidence in ('observed title=Pet Trainer; service=trainer',
                         'NPC under prof(197); teaches recipe(123); highest explicit profession rank=expert',
                         'NPC under prof(171); teaches recipe(123); highest explicit profession rank='):
            with self.subTest(evidence=evidence):
                bad = copy.deepcopy(data)
                bad['patterns'][title]['evidence'] = evidence
                with self.assertRaisesRegex(ValueError, 'lacks prior trainer evidence'):
                    build.validate_records(bad)
        title = next(t for t, p in data['patterns'].items() if p['basis'] == 'window')
        data['npcs'][data['patterns'][title]['npc_id']]['window']['record'] = {}
        with self.assertRaisesRegex(ValueError, 'lacks trainer window'):
            build.validate_records(data)

    def test_malformed_fallback_coordinates(self):
        for position in (':0.5,0.5', '0:0.5,0.5', '999999:0.5,0.5', '37:NaN,0.5',
                         '37:inf,0.5', '37:-0.1,0.5', '37:0.5', '37:0.5,', '37:1.1,0.5'):
            with self.subTest(position=position):
                def mutate(rows):
                    next(r for r in rows if r['positions'])['positions'] = position
                self.invalid(mutate, 'invalid trainer position')

    def test_unsafe_fallback_names(self):
        for name in ('|cffffffffName|r', '|Ttexture|t', 'Name\x00', 'Name]=]'):
            with self.subTest(name=name):
                def mutate(rows):
                    next(r for r in rows if r['positions'])['name_enUS'] = name
                self.invalid(mutate, 'unsafe trainer name')
        self.invalid(lambda rows: next(r for r in rows if r['positions']).update(name_enUS='Invented'), 'lack pinned evidence/name')
        # Raw malformed UTF-8 must fail the same fixture reader, before generation.
        for raw in (b'\xff', b'\xe2\x82', b'\xc0\xaf'):
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'bad.tsv'
                path.write_bytes(build.FIXTURE.read_bytes() + raw)
                with self.assertRaises(UnicodeDecodeError):
                    build.read_rows(path)

    def test_conflicting_class_rejected(self):
        def mutate(rows):
            row = next(r for r in rows if r['kind'] == 'class').copy()
            row['subkind'] = 'warrior' if row['subkind'] != 'warrior' else 'mage'
            rows.append(row)
        self.invalid(mutate, 'conflicting class subkinds')

    def test_single_row_role_and_faction_mutations(self):
        # Exercise each source family and mixed evidence, with one changed row.
        # No duplicate-ID guard or stale-output/checksum check can mask the gate.
        selectors = {
            'att': lambda r: build.SOURCE not in r['source'] and 'ATTWoWAddon' in r['source'],
            'forever': lambda r: build.SOURCE not in r['source'] and '/Forever.lua' in r['source'],
            'observed': lambda r: r['source'].startswith(build.SOURCE),
            'mixed': lambda r: build.SOURCE in r['source'] and not r['source'].startswith(build.SOURCE),
        }
        mutations = [
            ('wrong class', lambda r: r['kind'] == 'class', dict(subkind='warrior')),
            ('wrong profession', lambda r: r['kind'] == 'profession', dict(subkind='mining')),
            ('wrong faction', lambda r: r['faction'] in ('A','H'), dict(faction='H')),
            ('kind/subkind swap', lambda r: r['kind'] in ('weapon', 'riding'), dict(kind='class', subkind='mage')),
        ]
        for source, select in selectors.items():
            for label, eligible, change in mutations:
                rows = build.read_rows()
                candidates = [r for r in rows if select(r) and eligible(r)
                              and (label == 'wrong faction' or any(r[k] != v for k, v in change.items()))]
                if not candidates:
                    continue  # This source has no such role/faction assertion.
                ident = candidates[0]['npc_id']
                if label == 'wrong faction':
                    change = dict(faction='H' if candidates[0]['faction'] == 'A' else 'A')
                with self.subTest(source=source, mutation=label, npc=ident):
                    def mutate(rows):
                        next(r for r in rows if r['npc_id'] == ident).update(change)
                    self.invalid(mutate, 'title|profession|faction')
        # Both empty-subkind roles must reject a valid kind/subkind substitution.
        for kind, other in [('weapon','riding'), ('riding','weapon')]:
            with self.subTest(swap=kind):
                self.invalid(lambda rows: next(r for r in rows if r['kind'] == kind).update(kind=other), 'title')

    def test_literal_evidence_cannot_disagree_with_pinned_role_or_faction(self):
        def mutate(rows):
            next(r for r in rows if r['npc_id'] == '3597').update(evidence='not actually a trainer; faction=packaged units')
        self.invalid(mutate, 'unrecognized literal trainer evidence')
        def contradictory(rows):
            row = next(r for r in rows if r['source'].startswith(build.SOURCE) and r['faction'] == 'H')
            row['evidence'] += ' | explicit NPC title <Druid Trainer>; faction=side=Alliance'
        self.invalid(contradictory, 'title|faction')
        def title(rows):
            row = next(r for r in rows if r['npc_id'] == '4892')
            row['evidence'] = row['evidence'].replace('Hunter Trainer & Bowyer','Mage Trainer')
        self.invalid(title, 'literal title role')
        def faction(rows):
            row = next(r for r in rows if 'faction=side=Horde' in r['evidence'])
            row['evidence'] = row['evidence'].replace('faction=side=Horde','faction=side=Alliance')
        self.invalid(faction, 'faction contradicts')

    def test_source_and_licence_allowlist(self):
        self.invalid(lambda rows: rows[0].update(source='https://example.org/trainers'), 'unrecorded source')
        self.invalid(lambda rows: rows[0].update(licence='GPL'), 'unrecorded licence/source')
        def mutate(rows):
            row = next(r for r in rows if build.SOURCE in r['source'])
            row['source'] += ' | ' + build.SOURCE + 'invented.json'
        self.invalid(mutate, 'unrecorded evidence path')

    def test_title_and_pattern_corroboration(self):
        c = build.classify
        self.assertIsNone(c('Herbalist'))
        self.assertEqual(c('Herbalist', True), ('profession', 'herbalism'))
        self.assertIsNone(c('Expert Blacksmith'))
        self.assertEqual(c('Expert Blacksmith', False, {'Expert Blacksmith'}), ('profession', 'blacksmithing'))
        for title in ('Alchemy Supplies', 'Master Mage', 'Rogue Trainer?', 'Master Weaponsmith', 'Superior Herbalist', 'Invented Riding Trainer'):
            self.assertIsNone(c(title, True), title)
        data = json.loads(build.EVIDENCE.read_text())
        title = next(t for t, p in data['patterns'].items() if p['basis'] == 'window')
        del data['npcs'][data['patterns'][title]['npc_id']]['window']
        with self.assertRaisesRegex(ValueError, 'lacks trainer window'):
            build.validate_records(data)
        def mutate(rows):
            row = next(r for r in rows if build.SOURCE in r['source'])
            row['evidence'] = 'title=Invented Trainer;'
        self.invalid(mutate, 'title-pattern corroboration/evidence')

    def test_positions_only_fill_absent_database_positions(self):
        def mutate(rows):
            row = next(r for r in rows if r['npc_id'] in build.database_position_ids())
            row.update(positions='1453:0.5,0.5', name_enUS='Invented position')
        self.invalid(mutate, 'replace database positions')
        def unpinned(rows):
            row = next(r for r in rows if r['positions'])
            row['positions'] = '1453:0.123456,0.654321'
        self.invalid(unpinned, 'lack pinned evidence')
        def invalid(rows):
            row = next(r for r in rows if r['positions'])
            row['positions'] = '1453:5,0.5'
        self.invalid(invalid, 'invalid trainer position')

    def test_unknown_factions_excluded_from_generated_lists(self):
        rows = build.read_rows()
        text = build.generate(rows).split('WaypointTrackerData.trainerLocations')[0]
        for row in rows:
            if not row['faction']:
                self.assertNotIn(row['npc_id'] + ':', text)
        def mutate(rows):
            row = next(r for r in rows if not r['faction'] and build.SOURCE in r['source'])
            row['faction'] = 'A'
        self.invalid(mutate, 'faction lacks pinned evidence')

    def test_reviewed_position_corrections_follow_newest_observations(self):
        import csv
        from decimal import Decimal, ROUND_HALF_UP
        from stage_quest_corrections import corrected
        data = json.loads(build.EVIDENCE.read_text())
        with (ROOT / 'tools/corrections_trainers.tsv').open() as stream:
            corrections = list(csv.DictReader(stream, delimiter='\t'))
        source = (ROOT / 'WaypointTracker_Data/Curated.lua').read_text()
        original = source
        for row in corrections:
            ident = row['record'][1:]
            proof = data['npcs'][ident]['position']
            position = proof['record']['positions'][0]
            # Retain the format's 0.1% precision; never average source points.
            x, y = (int((Decimal(str(position[k])) * 1000).quantize(Decimal('1'), rounding=ROUND_HALF_UP))
                    for k in ('mapX','mapY'))
            self.assertEqual(row['value'], f"{position['uiMap']}:{x},{y}")
            self.assertIn(proof['path'], data['files'])
            actual = next(line for line in source.splitlines() if line.startswith('N\t' + ident + '\t'))
            self.assertEqual(actual.split('\t')[6], row['value'], ident + ' published position resolution')
            original = original.replace(actual, actual.replace(row['value'], row['expected']))
        reapplied, additions = corrected(original, corrections)
        self.assertEqual(reapplied, source)
        self.assertFalse(additions)
        with self.assertRaisesRegex(ValueError, 'Stale expected value'):
            corrected(source, corrections)
        rows = build.read_rows()
        for ident in ('251991','257020'):
            self.assertIn('newest positioned Forever observation', next(r['evidence'] for r in rows if r['npc_id'] == ident))

    def test_evidence_fixture_checksums(self):
        manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
        for path in build.EVIDENCE.parent.iterdir():
            key = path.relative_to(ROOT / 'tools/fixtures').as_posix()
            self.assertEqual(manifest[key]['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()
