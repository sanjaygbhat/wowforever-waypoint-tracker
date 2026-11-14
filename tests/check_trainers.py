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
sys.path.insert(0, str(ROOT / 'tests'))
import trainer_coverage


class Trainers(unittest.TestCase):
    def test_generated_current(self):
        self.assertEqual(build.OUTPUT.read_text(), build.generate(build.read_rows()))

    def test_fixture_pinned(self):
        manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
        self.assertEqual(manifest['trainers/trainers.tsv']['sha256'], hashlib.sha256(build.FIXTURE.read_bytes()).hexdigest())

    def test_deterministic_and_compact(self):
        rows = build.read_rows()
        self.assertEqual(build.generate(rows), build.generate(list(reversed(rows))))
        # Full-precision observations now replace older shipped coordinates.
        # Keep their separate footprint bounded, rather than dropping evidence.
        self.assertLess(len(build.generate(rows).encode()), 24576)
        self.assertLess(len(build.generate([dict(r, positions='') for r in rows]).encode()), 6144)
        self.assertIn('trainer_pet_hunter', build.generate(rows))
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
            row.update(positions='1453:0.5,0.5', name_enUS='Invented position', position_mode='fallback')
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
        for path in list(build.EVIDENCE.parent.iterdir()) + list(build.REFRESH_EVIDENCE.parent.iterdir()) + list(build.ATT_EVIDENCE.parent.iterdir()) + list(build.PLAYER_EVIDENCE.parent.iterdir()):
            key = path.relative_to(ROOT / 'tools/fixtures').as_posix()
            self.assertEqual(manifest[key]['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_refreshed_sources_reject_mutations(self):
        for pin in (build.REFRESH_PIN, build.ATT_PIN):
            for label, change in [('role', dict(kind='class', subkind='warrior')),
                                  ('faction', dict(faction='AH')),
                                  ('title', dict(evidence='title=Invented Trainer; faction=unknown;'))]:
                with self.subTest(pin=pin, mutation=label):
                    def mutate(rows):
                        row = next(r for r in rows if pin in r['source'] and r['kind'] == 'profession')
                        row.update(change)
                    self.invalid(mutate, 'role|title|faction|profession|record|literal')
        self.assertIsNone(build.classify('Medic'))
        self.assertIsNone(build.classify('Fisher'))
        self.assertIsNone(build.classify('Superior Fisherman'))
        self.assertEqual(build.classify('Medic', True), ('profession', 'firstaid'))

    def test_observed_coordinates_cannot_become_unpinned_overrides(self):
        def mutate(rows):
            row = next(r for r in rows if r['position_mode'] == 'observed')
            row.update(positions='1453:0.123,0.987')
        self.invalid(mutate, 'lack pinned evidence')
        self.invalid(lambda rows: rows[0].update(position_mode='invented'), 'unknown trainer position mode')

    def test_fact_source_row_mutations(self):
        for label, change in [('role', dict(subkind='mining')), ('faction', dict(faction='')), ('rank', dict(rank='artisan')), ('record', dict(evidence='NPC role facts; records=999999; consensus=vmangos'))]:
            def mutate(rows):
                row = next(r for r in rows if r['evidence'].startswith('NPC role facts;') and r['kind'] == 'profession' and r['subkind'] != 'mining' and r['rank'] != 'artisan')
                row.update(change)
            with self.subTest(mutation=label):
                self.invalid(mutate, 'fact|role|faction|rank|source')

    def test_numeric_roles_require_trainer_flags_and_correct_class(self):
        record = dict(npc_flags=16, trainer_type=0, trainer_class=8, subname='Mage Trainer')
        self.assertEqual(build.fact_roles(record), {('class', 'mage')})
        self.assertFalse(build.fact_roles(dict(record, npc_flags=128)))
        self.assertEqual(build.fact_roles(dict(record, trainer_class=4)), {('class', 'rogue')})
        # A supplied skill-line witness takes precedence over an ambiguous title.
        record = dict(npc_flags=16, trainer_type=2, subname='Artisan Alchemist', trainer_spells=[dict(reqskill=333)])
        self.assertEqual(build.fact_roles(record), {('profession', 'enchanting')})
        self.assertFalse(build.fact_roles(dict(record, npc_flags=0)))

    def test_explicit_rank_is_teaching_effect_not_occupational_title(self):
        source = build.fact_sources()['cmangos']
        record = source['records']['4160']
        self.assertEqual(build.fact_rank(record, source['spell_facts'], 'alchemy'), 'expert')
        self.assertEqual(build.fact_rank(record, {}, 'alchemy'), '')
        self.assertEqual(build.fact_rank(record, source['spell_facts'], 'mining'), '')

    def test_neutral_and_alliance_shaman_access_is_pinned(self):
        rows = build.read_rows()
        for ident in ('257446', '258098', '258113'):
            row = next(r for r in rows if r['npc_id'] == ident)
            self.assertEqual(row['faction'], 'A')
            self.assertIn('ATT quest access; record=' + ident, row['evidence'])
            self.invalid(lambda rows: next(r for r in rows if r['npc_id'] == ident).update(faction='H'), 'access|faction|literal')
        self.assertEqual(next(r for r in rows if r['npc_id'] == '12042')['faction'], 'AH')
        self.invalid(lambda rows: next(r for r in rows if r['npc_id'] == '12042').update(faction='H'), 'fact|faction|unrecognized')
        self.invalid(lambda rows: next(r for r in rows if r['npc_id'] == '258098').update(positions='1455:0.1,0.2'), 'ATT positions')

    def test_active_classic_census_cannot_silently_lose_a_trainer(self):
        rows = build.read_rows()
        ids = {r['npc_id'] for r in rows}
        fresh = json.loads(build.REFRESH_EVIDENCE.read_text())['npcs']
        facts = build.fact_sources()
        for ident in set().union(*(set(d['records']) for d in facts.values())):
            accepted, roles = build.fact_consensus(ident)
            if not accepted or not any(d['records'].get(ident, {}).get('spawns') for d in facts.values()):
                continue
            literal = build.classify(fresh.get(ident, {}).get('title', {}).get('record', {}).get('title', ''), True)
            if literal and literal not in accepted:
                continue  # Higher-priority Forever role, independently retained.
            negative = any(ident in d['records'] and not d['records'][ident].get('npc_flags', 0) & 16 for d in facts.values())
            if negative and not any(sum(role in r for r in roles.values()) >= 2 for role in accepted):
                continue
            self.assertIn(ident, ids, 'Active source trainer missing from roster: ' + ident)

    def test_emulator_world_conversion_matches_pinned_client_geometry(self):
        resolver = trainer_coverage.Resolver()
        for ident in ('377', '4160', '2998', '12042'):
            positions = build.emulator_positions(ident)
            self.assertTrue(positions, ident)
            spawns = build.fact_sources()['vmangos']['records'][ident]['spawns']
            for point in positions:
                cont, wx, wy = resolver.world(point)
                self.assertTrue(any(cont == p['map'] and abs(wx - p['position_x']) < 1e-8 and abs(wy - p['position_y']) < 1e-8 for p in spawns))
        # The client has no Uldaman uiMap. A dungeon spawn must not become a
        # fabricated surface/entrance coordinate.
        self.assertEqual(build.emulator_positions('11073'), [])

    def test_fact_fixtures_and_review_checksums(self):
        manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
        for folder, repo, pin, licence in build.FACT_SOURCES.values():
            for path in (build.FIXTURE.parent / folder).iterdir():
                key = path.relative_to(ROOT / 'tools/fixtures').as_posix()
                self.assertEqual(manifest[key]['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())


    def test_disputed_flags_and_rank_do_not_gain_access_or_a_tier(self):
        # Bowen Brisboise: CMaNGOS marks a trainer, VMaNGOS and Questie don't.
        accepted, _ = build.fact_consensus('3530')
        self.assertFalse(accepted)
        self.assertNotIn('3530', {r['npc_id'] for r in build.read_rows()})
        # Katoom: numeric teaching tiers differ, so the roster makes no claim.
        self.assertEqual(build.fact_row_rank('14740', 'fishing'), '')
        self.assertEqual(next(r for r in build.read_rows() if r['npc_id'] == '14740')['rank'], '')


    def test_player_coordinates_and_relationship_are_literal_and_newest(self):
        build_id, points = build.player_positions('2326')
        self.assertEqual(build_id, 70450)
        self.assertEqual(points, [(1426, 0.473, 0.526)])
        self.assertNotIn('251374', build.player_records()['npcs'])  # newer EG position
        self.assertNotIn('251376', build.player_records()['npcs'])  # same build, finer EG position
        rows = build.read_rows()
        self.assertEqual(next(r for r in rows if r['npc_id'] == '251379')['faction'], 'A')
        self.assertEqual(next(r for r in rows if r['npc_id'] == '258113')['positions'], '1426:0.472,0.519')
        self.invalid(lambda rows: next(r for r in rows if r['npc_id'] == '258113').update(positions='1426:0.1,0.2'), 'player positions')
        self.invalid(lambda rows: next(r for r in rows if r['npc_id'] == '251379').update(faction='H'), 'player quest access|faction')
        self.invalid(lambda rows: next(r for r in rows if r['npc_id'] == '460').update(evidence='observed title=Warlock Trainer; faction=packaged units | player position; record=460; build=99999'), 'player positions|title|faction')

    def test_root_review_and_client_fixture_checksums(self):
        manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
        for path in build.FIXTURE.parent.glob('*.json'):
            key = path.relative_to(ROOT / 'tools/fixtures').as_posix()
            self.assertEqual(manifest[key]['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())


    def test_capital_coverage(self):
        matrix, gaps = trainer_coverage.coverage_gaps(build.read_rows(), build.CLASSES, build.PROFESSIONS)
        trainer_coverage.print_matrix(matrix, build.CLASSES, build.PROFESSIONS)
        self.assertFalse(gaps, 'Unresolved trainer coverage (no evidence-backed absence): ' + repr(gaps))
        trainer_coverage.print_towns(trainer_coverage.town_matrix(build.read_rows()))

    def test_capital_gate_detects_missing_supported_service(self):
        rows = build.read_rows()
        _, before = trainer_coverage.coverage_gaps(rows, build.CLASSES, build.PROFESSIONS, '')
        # Removing every alchemist must add six failures, even where other
        # professions and class trainers remain present in the same city.
        rows = [r for r in rows if (r['kind'], r['subkind']) != ('profession', 'alchemy')]
        _, after = trainer_coverage.coverage_gaps(rows, build.CLASSES, build.PROFESSIONS, '')
        self.assertEqual(len(after) - len(before), 6)


if __name__ == '__main__':
    unittest.main()
