#!/usr/bin/env python3
"""Build compact trainer identities and missing-position fallbacks; no network.

Add further sources as fixture rows with their own source URL and evidence.
The runtime format deliberately contains no source-specific behavior.
"""
import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tools/fixtures/trainers/trainers.tsv'
OUTPUT = ROOT / 'WaypointTracker_Data/Trainers.lua'
EVIDENCE = FIXTURE.parent / 'observed-164bd1e2/records.json'
PIN = '164bd1e2d89579ada4ee5e2de7e5fd4db684a9f1'
SOURCE = 'https://github.com/JIVESCORP/eg-link-output-wowf/blob/' + PIN + '/'
SOURCE_PREFIXES = (
    'https://github.com/ATTWoWAddon/AllTheThings/blob/ec1aa307198d92d18c601ae2c9338a67b71e7d6b/',
    'https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/b3f68f8da465dbd27b13e0b46a46f9a405a2f762/WaypointTracker_Data/Forever.lua#L',
    SOURCE,
)
CLASSES = 'warrior paladin hunter rogue priest shaman mage warlock druid'.split()
PROFESSIONS = 'alchemy blacksmithing enchanting engineering herbalism leatherworking mining skinning tailoring cooking firstaid fishing'.split()
SUBKINDS = dict(class_=CLASSES, profession=PROFESSIONS, weapon=[''], riding=[''], pet=['hunter'], demon=['warlock'], portal=['mage'])
SUBKINDS['class'] = SUBKINDS.pop('class_')
PROFESSION_IDS = dict(zip(PROFESSIONS, [171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356]))
# Exact English titles in the pinned sources, including approved compounds.
# This is the single role oracle for all sources and evidence assertions.
TITLE_GROUPS = {
    ('class', 'druid'): ['Druid Trainer'],
    ('class', 'hunter'): ['Hunter Trainer', 'Hunter Trainer & Bowyer'],
    ('class', 'mage'): ['Mage Trainer'],
    ('class', 'paladin'): ['Paladin Trainer'],
    ('class', 'priest'): ['Priest Trainer'],
    ('class', 'rogue'): ['Rogue Trainer'],
    ('class', 'shaman'): ['Shaman Trainer'],
    ('class', 'warlock'): ['Warlock Trainer'],
    ('class', 'warrior'): ['Warrior Trainer'],
    ('weapon', ''): ['Weapon Master'],
    ('riding', ''): ['Riding Trainer', 'Kodo Riding Instructor', 'Raptor Riding Trainer',
                     'Undead Horse Riding Instructor', 'Wolf Riding Instructor'],
    ('pet', 'hunter'): ['Pet Trainer'],
    ('demon', 'warlock'): ['Demon Trainer'],
    ('portal', 'mage'): ['Portal Trainer'],
    ('profession', 'alchemy'): ['Alchemist', 'Journeyman Alchemist', 'Journeyman Alchemist Trainer',
        'Expert Alchemist', 'Artisan Alchemist', 'Master Alchemist'],
    ('profession', 'blacksmithing'): ['Blacksmith', 'Journeyman Blacksmith', 'Expert Blacksmith',
        'Artisan Blacksmith', 'Master Blacksmith'],
    ('profession', 'enchanting'): ['Enchanter', 'Journeyman Enchanter', 'Expert Enchanter',
        'Artisan Enchanter', 'Enchanting Trainer'],
    ('profession', 'engineering'): ['Journeyman Engineer', 'Expert Engineer', 'Artisan Engineer',
        'Master Engineer', 'Master Goblin Engineer', 'Goblin Engineering Trainer'],
    ('profession', 'herbalism'): ['Herbalist', 'Apprentice Herbalist', 'Herbalism Trainer', 'Junior Herbalism Trainer'],
    ('profession', 'leatherworking'): ['Leatherworker', 'Journeyman Leatherworker', 'Expert Leatherworker',
        'Artisan Leatherworker', 'Master Leatherworker', 'Tribal Leatherworking Trainer'],
    ('profession', 'mining'): ['Miner', 'Mining Trainer', 'Junior Mining Trainer'],
    ('profession', 'skinning'): ['Skinner', 'Skinning Trainer', 'Junior Skinning Trainer'],
    ('profession', 'tailoring'): ['Tailor', 'Journeyman Tailor', 'Expert Tailor', 'Artisan Tailor', 'Master Tailor'],
    ('profession', 'cooking'): ['Cook', 'Cooking Trainer'],
    ('profession', 'firstaid'): ['Physician', 'First Aid Trainer'],
    ('profession', 'fishing'): ['Fisherman', 'Fishing Trainer'],
}
TITLE_ROLES = {title: role for role, titles in TITLE_GROUPS.items() for title in titles}
# Occupational titles require a real window/interaction or a pinned witness.
OCCUPATIONAL = {title for title, role in TITLE_ROLES.items()
                if role[0] == 'profession' and ('Trainer' not in title or title == 'Journeyman Alchemist Trainer')}


def classify(title, interaction=False, corroborated=()):
    """Only exact, corroborated literal titles establish a trainer role."""
    role = TITLE_ROLES.get(title)
    if title in OCCUPATIONAL and not (interaction or title in corroborated):
        return None
    return role


def packaged_units():
    text = (ROOT / 'WaypointTracker_Data/Data.lua').read_text()
    block = text.split('units = [==[\n', 1)[1].split(']==]', 1)[0]
    return {f[0]: f for f in (line.split('\t') for line in block.splitlines())}


def database_position_ids():
    """Conservatively count every shipped position before trainer fallbacks.

    Curated/Forever replace or supplement raw positions at runtime; personal
    discoveries cannot be known offline and are checked again on each request.
    """
    ids = {i for i, f in packaged_units().items() if f[4]}
    for name in ('Curated.lua', 'Forever.lua'):
        for line in (ROOT / 'WaypointTracker_Data' / name).read_text().splitlines():
            f = line.split('\t')
            if f[0] == 'N' and len(f) > 6 and f[6]:
                ids.add(f[1])
    return ids


def position_list(value):
    out = []
    with (ROOT / 'tools/fixtures/client/UiMap-1.60.1.70862-enUS.csv').open() as stream:
        maps = {int(r['ID']) for r in csv.DictReader(stream)}
    for item in value.split(';') if value else []:
        try:
            if not re.fullmatch(r'[0-9]+:[0-9]+(?:\.[0-9]+)?,[0-9]+(?:\.[0-9]+)?', item):
                raise ValueError()
            m, xy = item.split(':')
            x, y = map(float, xy.split(','))
            if not re.fullmatch(r'[0-9]+', m) or int(m) not in maps or not (0 <= x <= 1 and 0 <= y <= 1):
                raise ValueError()
        except ValueError:
            raise ValueError('invalid trainer position: ' + value) from None
        out.append((int(m), x, y))
    return out


def validate_records(records):
    for title, proof in records['patterns'].items():
        witness = records['npcs'].get(proof['npc_id'], {})
        if witness.get('title', {}).get('record', {}).get('title') != title:
            raise ValueError('title-pattern witness mismatch: ' + title)
        if proof['basis'] == 'window':
            if not trainer_window(witness):
                raise ValueError('title-pattern lacks trainer window: ' + title)
        elif proof['basis'] != 'prior fixture' or not proof.get('source') or not trainer_evidence(proof.get('evidence', ''), (classify(title, True) or ('', None))[1]) or not all(
                url.startswith(SOURCE_PREFIXES[:2]) for url in proof.get('source', '').split(' | ')):
            raise ValueError('title-pattern lacks prior trainer evidence: ' + title)


def observed_faction(record, ident, units):
    side = record.get('side', {}).get('record', {}).get('side')
    if side in ('Alliance', 'Horde'):
        return {'Alliance': 'A', 'Horde': 'H'}[side]
    reactions = record.get('reaction', {}).get('record', {}).get('reactions', {})
    fac = ''.join(letter for side, letter in [('Alliance', 'A'), ('Horde', 'H')]
                  if reactions.get(side) and min(reactions[side]) >= 5)
    return fac or (units.get(str(ident), ['', '', ''])[2] if str(ident) in units else '')


def trainer_evidence(evidence, profession=None, rank=None):
    """Require a complete assertion identifying this profession, not a keyword."""
    for part in evidence.split(' | '):
        part = re.sub(r'; faction=(?:packaged units|unknown)$', '', part)
        match = re.fullmatch(r'NPC under prof\((\d+)\); teaches recipe\(\d+\); highest explicit profession rank=(apprentice|journeyman|expert|artisan)', part)
        if match:
            key = next((k for k, v in PROFESSION_IDS.items() if v == int(match[1])), None)
            if key and (profession is None or key == profession) and (rank is None or rank == match[2]):
                return True
        explicit = re.fullmatch(r'explicit NPC title <([^<>]+)>(?:; faction=packaged units)?', part)
        observed = re.fullmatch(r'observed title=([^;]+)(; service=trainer)?', part)
        title = explicit[1] if explicit else observed[1] if observed else None
        if title and ('Trainer' in title or (observed and observed[2])):
            role = classify(title, True)
            if role and role[0] == 'profession' and (profession is None or role[1] == profession):
                return True
    return False


def validate_assertions(row, units):
    """Check every literal assertion, including earlier sources in mixed rows."""
    expected = row['kind'], row['subkind']
    ident = row['npc_id']
    factions = []
    for part in row['evidence'].split(' | '):
        title = re.match(r'explicit NPC title <([^<>]+)>', part)
        if not title:
            title = re.match(r'(?:observed )?title=([^;]+)', part)
        if not title:
            title = re.match(r'(?:explicit |NPC under )(Demon Trainer|Riding Trainer|Weapon Master) header\(-(?:25|48|59)\)', part)
        if title and ' header(' in part:
            header = {'Demon Trainer': '-25', 'Riding Trainer': '-48', 'Weapon Master': '-59'}[title[1]]
            if 'header(' + header + ')' not in part:
                raise ValueError('literal header role contradicts kind/subkind: ' + ident)
        recipe = re.match(r'NPC under prof\((\d+)\); teaches recipe\(\d+\); highest explicit profession rank=(apprentice|journeyman|expert|artisan)(?:;|$)', part)
        if title:
            if TITLE_ROLES.get(title[1]) != expected:
                raise ValueError('literal title role contradicts kind/subkind: ' + ident)
        elif recipe:
            key = next((k for k, v in PROFESSION_IDS.items() if v == int(recipe[1])), None)
            if expected != ('profession', key) or recipe[2] != row['rank']:
                raise ValueError('profession lacks trainer evidence: ' + ident)
        else:
            raise ValueError('unrecognized literal trainer evidence: ' + ident)
        faction = re.search(r'(?:^|; )faction=([^;]+)', part)
        if not faction:
            continue
        factions.append(faction[1])
        basis = faction[1]
        if basis == 'packaged units':
            if row['faction'] != units.get(ident, ['', '', ''])[2]:
                raise ValueError('faction contradicts packaged units: ' + ident)
        elif basis == 'unknown':
            if row['faction']:
                raise ValueError('faction contradicts unknown evidence: ' + ident)
        elif basis.startswith('side='):
            if row['faction'] != {'side=Alliance': 'A', 'side=Horde': 'H'}.get(basis):
                raise ValueError('faction contradicts literal side evidence: ' + ident)
        elif basis.startswith('friendly reaction='):
            if row['faction'] != basis.removeprefix('friendly reaction='):
                raise ValueError('faction contradicts literal reaction evidence: ' + ident)
        else:
            raise ValueError('unrecognized faction evidence: ' + ident)

    if not factions:
        raise ValueError('faction evidence missing (mark packaged derivation): ' + ident)


def safe_name(value):
    try:
        value.encode('utf-8', errors='strict')
    except UnicodeError:
        raise ValueError('invalid trainer name UTF-8') from None
    if any(ord(c) < 32 or ord(c) == 127 for c in value) or '|' in value or ']=]' in value:
        raise ValueError('unsafe trainer name')


def trainer_window(record):
    window = record.get('window', {}).get('record', {})
    return window.get('tradeskill') is True and window.get('trainerType') == 2


def read_rows(path=FIXTURE):
    with path.open(encoding='utf-8', newline='') as stream:
        rows = list(csv.DictReader(stream, delimiter='\t'))
    records = json.loads(EVIDENCE.read_text()) if EVIDENCE.exists() else {'npcs': {}, 'patterns': {}}
    validate_records(records)
    positioned, units = database_position_ids(), packaged_units()
    seen, classes, roles = set(), {}, {}
    for row in rows:
        ident, kind, subkind = int(row['npc_id']), row['kind'], row['subkind']
        if ident <= 0 or kind not in SUBKINDS or subkind not in SUBKINDS[kind]:
            raise ValueError('unknown kind/subkind or invalid id: ' + str(row))
        if kind == 'class':
            if ident in classes and classes[ident] != subkind:
                raise ValueError('conflicting class subkinds: ' + str(ident))
            classes[ident] = subkind
        if ident in roles and roles[ident] != (kind, subkind):
            raise ValueError('conflicting trainer roles: ' + str(ident))
        roles[ident] = kind, subkind
        if not row['source'].startswith('https://') or not row['evidence'].strip():
            raise ValueError('missing source/evidence: ' + str(ident))
        if any(not url.startswith(SOURCE_PREFIXES) for url in row['source'].split(' | ')):
            raise ValueError('unrecorded source: ' + str(ident))
        observed = any(url.startswith(SOURCE) for url in row['source'].split(' | '))
        licences = ' | '.join(dict.fromkeys('CC BY 4.0' if url.startswith(SOURCE) else 'MIT' for url in row['source'].split(' | ')))
        if row.get('licence') != licences:
            raise ValueError('unrecorded licence/source: ' + str(ident))
        if observed:
            record = records['npcs'].get(str(ident), {})
            paths = {v['path'] for v in record.values()}
            if any(url[len(SOURCE):] not in paths for url in row['source'].split(' | ') if url.startswith(SOURCE)):
                raise ValueError('unrecorded evidence path: ' + str(ident))
            title = record.get('title', {}).get('record', {}).get('title', '')
            interaction = trainer_window(record) or 'TradeskillTrainer' in record.get('npc', {}).get('record', {}).get('interactions', [])
            if classify(title, interaction, records['patterns']) != (kind, subkind) or ('title=' + title + ';') not in row['evidence']:
                raise ValueError('title-pattern corroboration/evidence: ' + str(ident))
            if row['faction'] != observed_faction(record, ident, units):
                raise ValueError('faction lacks pinned evidence: ' + str(ident))
        if kind == 'profession' and not observed and not trainer_evidence(row['evidence'], subkind, row['rank']):
            raise ValueError('profession lacks trainer evidence: ' + str(ident))
        validate_assertions(row, units)
        if row['faction'] not in ('', 'A', 'H', 'AH') or row['rank'] not in ('', 'apprentice', 'journeyman', 'expert', 'artisan') or row['has_position'] not in ('yes', 'no'):
            raise ValueError('invalid metadata: ' + str(ident))
        safe_name(row.get('name_enUS', ''))
        positions = position_list(row.get('positions', ''))
        if positions:
            if str(ident) in positioned:
                raise ValueError('trainer positions replace database positions: ' + str(ident))
            record = records['npcs'].get(str(ident), {})
            allowed = {(p['uiMap'], p['mapX'], p['mapY']) for p in record.get('position', {}).get('record', {}).get('positions', [])}
            pinned_name = record.get('title', {}).get('record', {}).get('name')
            if not observed or not set(positions) <= allowed or not row.get('name_enUS') or row['name_enUS'] != pinned_name:
                raise ValueError('trainer positions lack pinned evidence/name: ' + str(ident))
        key = ident, kind, subkind
        if key in seen:
            raise ValueError('duplicate trainer: ' + str(key))
        seen.add(key)
    return sorted(rows, key=lambda r: (r['kind'], r['subkind'], int(r['npc_id'])))


def generate(rows):
    groups = defaultdict(list)
    locations = []
    for row in sorted(rows, key=lambda r: (r['kind'], r['subkind'], int(r['npc_id']))):
        # Extras remain reviewable in the fixture, unexposed this release.
        if row['kind'] not in ('class', 'profession', 'weapon', 'riding'):
            continue
        if not row['faction']:
            continue
        key = 'trainer_' + row['kind'] + ('_' + row['subkind'] if row['subkind'] else '')
        groups[key].append(row['npc_id'] + ':' + row['faction'])
        if row.get('positions'):
            locations.append('\t'.join((row['npc_id'], row['name_enUS'], row['positions'])))
    lines = ['-- Generated by tools/build_trainers.py from tools/fixtures/trainers/trainers.tsv. Do not edit.',
             '-- Observed positions are fallbacks only, after database/learned positions.',
             'WaypointTrackerData.trainers = [=[']
    lines.extend(key + '\t' + ','.join(groups[key]) for key in sorted(groups))
    return '\n'.join(lines + [']=]', 'WaypointTrackerData.trainerLocations = [=['] + locations + [']=]', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    text = generate(read_rows())
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding='utf-8') != text:
            parser.exit(1, 'Trainers.lua is stale; run python3 tools/build_trainers.py\n')
    else:
        OUTPUT.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
