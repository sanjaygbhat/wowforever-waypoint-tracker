#!/usr/bin/env python3
"""Build compact trainer identities and missing-position fallbacks; no network.

Add further sources as fixture rows with their own source URL and evidence.
The runtime format deliberately contains no source-specific behavior.
"""
import argparse
import csv
import json
import re
from functools import lru_cache
from decimal import Decimal
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tools/fixtures/trainers/trainers.tsv'
OUTPUT = ROOT / 'WaypointTracker_Data/Trainers.lua'
EVIDENCE = FIXTURE.parent / 'observed-164bd1e2/records.json'
PIN = '164bd1e2d89579ada4ee5e2de7e5fd4db684a9f1'
SOURCE = 'https://github.com/JIVESCORP/eg-link-output-wowf/blob/' + PIN + '/'
REFRESH_PIN = 'e0f8585914c134d9cb5d76756bd065b1e3e92ece'
REFRESH_SOURCE = 'https://github.com/JIVESCORP/eg-link-output-wowf/blob/' + REFRESH_PIN + '/'
PLAYER_PIN = '24c719a76202d2b047392972b5d6770e1fc98a11'
PLAYER_SOURCE = 'https://github.com/salty-max/wow-data/blob/' + PLAYER_PIN + '/data/players/forever/enUS.json'
PLAYER_EVIDENCE = FIXTURE.parent / 'players-24c719a7/records.json'
ATT_PIN = '1c4d146b518a3c2cda6d2488a27be6e2638d5360'
ATT_SOURCE = 'https://github.com/ATTWoWAddon/AllTheThings/blob/' + ATT_PIN + '/'
REFRESH_EVIDENCE = FIXTURE.parent / ('observed-' + REFRESH_PIN[:8]) / 'records.json'
ATT_EVIDENCE = FIXTURE.parent / ('att-' + ATT_PIN[:8]) / 'records.json'
SOURCE_PREFIXES = (
    'https://github.com/ATTWoWAddon/AllTheThings/blob/ec1aa307198d92d18c601ae2c9338a67b71e7d6b/',
    'https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/b3f68f8da465dbd27b13e0b46a46f9a405a2f762/WaypointTracker_Data/Forever.lua#L',
    SOURCE,
    REFRESH_SOURCE,
    ATT_SOURCE,
    PLAYER_SOURCE,
    'https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip',
    'https://github.com/cmangos/classic-db/blob/c33f90b8eeb3f8bacb53d5cbfee45075c80b416c/',
    'https://github.com/Questie/Questie/blob/454b9d072965ee8f1a881429260fcf1fac8d60f7/',
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
    ('profession', 'firstaid'): ['Physician', 'Medic', 'First Aid Trainer'],
    ('profession', 'fishing'): ['Fisherman', 'Fisher', 'Superior Fisherman', 'Fishing Trainer'],
}
TITLE_ROLES = {title: role for role, titles in TITLE_GROUPS.items() for title in titles}
# Occupational titles require a real window/interaction or a pinned witness.
OCCUPATIONAL = {title for title, role in TITLE_ROLES.items()
                if role[0] == 'profession' and ('Trainer' not in title or title == 'Journeyman Alchemist Trainer')}


# Role and spawn facts only; no emulator implementation or source text is shipped.
FACT_SOURCES = {
    'vmangos': ('vmangos-1fb49098', 'vmangos/core', '1fb4909858f3ac558e06613e223f6d7116a9a8fa', 'GPL-2.0'),
    'cmangos': ('cmangos-c33f90b8', 'cmangos/classic-db', 'c33f90b8eeb3f8bacb53d5cbfee45075c80b416c', 'GPL-3.0'),
    'questie': ('questie-454b9d07', 'Questie/Questie', '454b9d072965ee8f1a881429260fcf1fac8d60f7', 'GPL-3.0 / historical mixed licensing'),
}
CLASS_IDS = dict(zip([1, 2, 3, 4, 5, 7, 8, 9, 11], CLASSES))
FACT_TITLES = {
    'Master Mage': ('class', 'mage'), 'High Priest': ('class', 'priest'),
    'Grand Master Rogue': ('class', 'rogue'),
    **{t: ('riding', '') for t in ['Horse Riding Instructor', 'Nightsaber Riding Instructor', 'Ram Riding Instructor', 'Mechanostrider Pilot']},
    **{t: ('profession', 'leatherworking') for t in ['Master Dragonscale Leatherworker', 'Master Elemental Leatherworker', 'Master Tribal Leatherworker', 'Expert Leathercrafter', 'Master Leatherworking Trainer', 'Leatherworking Trainer']},
    'Master Shadoweave Tailor': ('profession', 'tailoring'),
    'Master Gnome Engineer': ('profession', 'engineering'),
    'Fishing Trainer & Supplies': ('profession', 'fishing'),
    'Master Enchanter': ('profession', 'enchanting'),
    'Trauma Surgeon': ('profession', 'firstaid'),
    **{t.title() + ' Trainer': ('profession', t) for t in ['alchemy', 'engineering', 'tailoring']},
}


def fact_roles(record):
    """Derive roles from literal flags, trainer fields and taught skill lines."""
    if not record.get('npc_flags', 0) & 16:
        return set()
    title = TITLE_ROLES.get(record.get('subname')) or FACT_TITLES.get(record.get('subname'))
    if title and title[0] in ('portal', 'demon'):
        return {title}
    kind = record.get('trainer_type')
    if kind == 3:
        return {('pet', 'hunter')}
    if kind == 1:
        return {('riding', '')}
    if kind == 0 and record.get('trainer_class') in CLASS_IDS:
        return {('class', CLASS_IDS[record['trainer_class']])}
    skills = {v['reqskill'] for v in record.get('trainer_spells', [])}
    professions = {('profession', k) for k, v in PROFESSION_IDS.items() if v in skills}
    return professions or ({title} if title else set())


def fact_rank(record, spell_facts, subkind):
    """Highest explicitly taught skill rank, independently of occupational title."""
    ranks = []
    for row in record.get('trainer_spells', []):
        spell = spell_facts.get(str(row['spell']), {})
        # Effect 36 teaches another spell; effect 118 supplies its skill tier.
        taught = [spell] + [spell_facts.get(str(spell.get('effecttriggerspell' + str(n))), {})
                            for n in (1, 2, 3) if spell.get('effect' + str(n)) == 36]
        for actual in taught:
            for n in (1, 2, 3):
                if actual.get('effect' + str(n)) == 118 and actual.get('effectmiscvalue' + str(n)) == PROFESSION_IDS[subkind]:
                    rank = actual.get('effectbasepoints' + str(n), -1) + 1
                    if 1 <= rank <= 4:
                        ranks.append(rank)
    return ['', 'apprentice', 'journeyman', 'expert', 'artisan'][max(ranks, default=0)]


@lru_cache(maxsize=1)
def fact_sources():
    out = {}
    for key, (folder, repo, commit, licence) in FACT_SOURCES.items():
        data = json.loads((FIXTURE.parent / folder / 'records.json').read_text())
        if (data['repository'], data['commit'], data['licence']) != (repo, commit, licence):
            raise ValueError('trainer fact source pin/licence mismatch: ' + key)
        out[key] = data
    return out


def fact_consensus(ident):
    by = {k: fact_roles(v['records'].get(str(ident), {})) for k, v in fact_sources().items()}
    counts = defaultdict(int)
    for roles in by.values():
        for role in roles:
            counts[role] += 1
    # A single authoritative source may fill a gap; contradictory assertions
    # require agreement from two independently pinned sources.
    negative = any(str(ident) in data['records'] and not data['records'][str(ident)].get('npc_flags', 0) & 16 for data in fact_sources().values())
    return {r for r, n in counts.items() if n >= (2 if len(counts) > 1 or negative else 1)}, by


def emulator_positions(ident):
    """World yards to the smallest matching Forever zone rectangle.

    This is Geo.WorldToMap's math; world coordinates already incorporate the
    Classic bounds, so applying FromClassicMap again would double-transform.
    Dungeons without a client map remain unlocated, never entrance guesses.
    """
    with (ROOT / 'tools/fixtures/client/UiMap-1.60.1.70862-enUS.csv').open() as stream:
        maps = {int(r['ID']): r for r in csv.DictReader(stream)}
    rectangles = {}
    with (ROOT / 'tools/fixtures/client/UiMapAssignment-1.60.1.70862-enUS.csv').open() as stream:
        for row in csv.DictReader(stream):
            m = int(row['UiMapID'])
            if m in rectangles or maps.get(m, {}).get('Type') != '3' or any(float(row[k]) != v for k, v in [('UiMin_0', 0), ('UiMin_1', 0), ('UiMax_0', 1), ('UiMax_1', 1)]):
                continue
            top, left = float(row['Region_3']), float(row['Region_4'])
            width, height = left - float(row['Region_1']), top - float(row['Region_0'])
            if width and height:
                rectangles[m] = int(row['MapID']), top, left, width, height
    data = fact_sources()
    spawns = data['vmangos']['records'].get(ident, {}).get('spawns') or data['cmangos']['records'].get(ident, {}).get('spawns') or []
    out = set()
    for spawn in spawns:
        if not spawn.get('patch_min', 0) <= 10 <= spawn.get('patch_max', 10):
            continue
        choices = []
        for m, (cont, top, left, width, height) in rectangles.items():
            x, y = (left - spawn['position_y']) / width, (top - spawn['position_x']) / height
            if cont == spawn['map'] and 0 <= x <= 1 and 0 <= y <= 1:
                choices.append((abs(width * height), m, x, y))
        if choices:
            _, m, x, y = min(choices)
            out.add((m, x, y))
    return sorted(out)


def fact_row_rank(ident, subkind):
    """Keep an explicit tier only when positive numeric tier facts agree."""
    data = fact_sources()
    spells = data['cmangos'].get('spell_facts', {})
    c = fact_rank(data['cmangos']['records'].get(ident, {}), spells, subkind)
    v = fact_rank(data['vmangos']['records'].get(ident, {}), spells, subkind)
    return '' if c and v and c != v else c


def fact_url(data, ident):
    return (data.get('url') or 'https://github.com/' + data['repository'] + '/blob/' + data['commit'] + '/' + next(iter(data['files']))) + '#npc=' + str(ident)


def source_licence(url):
    for folder, repo, commit, licence in FACT_SOURCES.values():
        if url.startswith('https://github.com/' + repo + '/blob/' + commit + '/') or (repo == 'vmangos/core' and url.startswith('https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip')):
            return licence
    return 'CC BY 4.0' if url.startswith((SOURCE, REFRESH_SOURCE)) else 'MIT'


def validate_fact_row(row, refresh, units):
    ident = row['npc_id']
    accepted, by = fact_consensus(ident)
    if (row['kind'], row['subkind']) not in accepted:
        raise ValueError('trainer fact role lacks consensus: ' + ident)
    expected_urls = []
    for key, data in fact_sources().items():
        if (row['kind'], row['subkind']) in by[key]:
            expected_urls.append(fact_url(data, ident))
    current = refresh['npcs'].get(ident, {})
    expected_urls += list(dict.fromkeys(REFRESH_SOURCE + v['path'] for v in current.values()))
    if row.get('position_mode') == 'player':
        expected_urls.append(PLAYER_SOURCE)
    if row['source'].split(' | ') != expected_urls:
        raise ValueError('trainer fact source record mismatch: ' + ident)
    if row['evidence'].split(' | ')[0] != 'NPC role facts; records=' + ident + '; consensus=' + ','.join(k for k in by if (row['kind'], row['subkind']) in by[k]):
        raise ValueError('trainer fact literal evidence mismatch: ' + ident)
    records = [data['records'].get(ident, {}) for data in fact_sources().values()]
    if not any(r.get('spawns') for r in records):
        raise ValueError('trainer fact has no active spawn: ' + ident)
    literal_role = classify(current.get('title', {}).get('record', {}).get('title', ''), True)
    if literal_role and literal_role != (row['kind'], row['subkind']):
        raise ValueError('trainer facts contradict Forever role: ' + ident)
    expected_faction = observed_faction(current, ident, units)
    if not expected_faction:
        expected_faction = fact_sources()['questie']['records'].get(ident, {}).get('friendly') or ''
        for side, letter in [('Alliance', 'A'), ('Horde', 'H')]:
            reactions = current.get('reaction', {}).get('record', {}).get('reactions', {}).get(side, [])
            if reactions and min(reactions) <= 3:
                expected_faction = expected_faction.replace(letter, '')
    if row['faction'] != expected_faction:
        raise ValueError('trainer fact faction mismatch: ' + ident)
    if row['kind'] == 'profession':
        expected = fact_row_rank(ident, row['subkind'])
        if row['rank'] != expected:
            raise ValueError('trainer fact rank mismatch: ' + ident)
    elif row['rank']:
        raise ValueError('trainer fact unexpected rank: ' + ident)


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


@lru_cache(maxsize=1)
def player_records():
    data = json.loads(PLAYER_EVIDENCE.read_text())
    if data['commit'] != PLAYER_PIN or data['licence'] != 'MIT' or data['path'] != 'data/players/forever/enUS.json':
        raise ValueError('player trainer source pin/licence mismatch')
    return data


def player_positions(ident):
    record = player_records()['npcs'].get(str(ident), {})
    history = record.get('where', [])
    if not history:
        return None, []
    build = max(int(v[4]) for v in history)
    points = set()
    for fact in history:
        if fact[:3] != ['npc', str(ident), 'where']:
            raise ValueError('player coordinate fact record mismatch')
        if int(fact[4]) == build:
            m, x, y = json.loads(fact[3], parse_float=Decimal)
            points.add((m, float(Decimal(x) / 100), float(Decimal(y) / 100)))
    return build, sorted(points)


def access_proof(row, refresh, att, units):
    """Additional factual access may fill unknown access, never hostile access."""
    ident = row['npc_id']
    parts = row['evidence'].split(' | ')
    marker = 'access facts; questie friendlyToFaction=' + row['faction'] + '; record=' + ident
    att_marker = 'ATT quest access; record=' + ident
    player_marker = 'player quest access; record=' + ident + '; quest=92481'
    if player_marker in parts:
        relation = player_records().get('quest_enders', {}).get('92481', [])
        proof = att.get('player_access', {}).get(ident, {})
        literal = proof.get('literal', '')
        from urllib.parse import quote
        url = ATT_SOURCE + quote(proof.get('path', '')) + '#L' + str(proof.get('line', ''))
        if relation[:4] != ['quest', '92481', 'ender', 'npc:' + ident] or not literal.startswith('q(92481, {') or 'races = ALLIANCE_ONLY' not in literal or 'classes = { MAGE }' not in literal or (row['kind'], row['subkind'], row['faction']) != ('class', 'mage', 'A') or url not in row['source'].split(' | ') or PLAYER_SOURCE not in row['source'].split(' | '):
            raise ValueError('player quest access lacks pinned relationship/faction: ' + ident)
    elif marker in parts:
        data = fact_sources()['questie']
        record = data['records'].get(ident, {})
        expected = record.get('friendly') or ''
        current = refresh['npcs'].get(ident, {})
        for side, letter in [('Alliance', 'A'), ('Horde', 'H')]:
            reactions = current.get('reaction', {}).get('record', {}).get('reactions', {}).get(side, [])
            if reactions and min(reactions) <= 3:
                expected = expected.replace(letter, '')
        url = fact_url(data, ident)
        if not expected or row['faction'] != expected or url not in row['source'].split(' | ') or (row['kind'], row['subkind']) not in fact_roles(record):
            raise ValueError('trainer access facts mismatch: ' + ident)
    elif att_marker in parts:
        proof = att.get('access', {}).get(ident, {})
        literal = proof.get('literal', '')
        race_access = re.search(r'races\s*=\s*(?:ALLIANCE_SHAMANS|\{\s*(?:GNOME|SKYBORNE_ALLIANCE)\s*\})', literal)
        if row['faction'] != 'A' or not re.search(r'\b(?:qg\s*=\s*' + ident + r'\b|qgs\s*=\s*\{[^}]*\b' + ident + r'\b)', literal, re.S) or not race_access or ('classes = { ' + row['subkind'].upper() + ' }') not in literal or row['kind'] != 'class':
            raise ValueError('ATT quest access lacks pinned class/faction: ' + ident)
    else:
        return False
    known = observed_faction(refresh['npcs'].get(ident, {}), ident, units)
    if known and known != row['faction']:
        raise ValueError('trainer access contradicts Forever evidence: ' + ident)
    return True


def validate_assertions(row, units, access=False):
    """Check every literal assertion, including earlier sources in mixed rows."""
    expected = row['kind'], row['subkind']
    ident = row['npc_id']
    factions = []
    for part in row['evidence'].split(' | '):
        if access and (part.startswith('access facts;') or part.startswith('ATT quest access;') or part.startswith('player quest access;')):
            continue
        if part.startswith('player position;'):
            if not re.fullmatch(r'player position; record=' + ident + r'; build=[0-9]+', part):
                raise ValueError('unrecognized player position evidence: ' + ident)
            continue
        if part.startswith('positioned observation; newest positioned Forever observation='):
            if not re.fullmatch(r'positioned observation; newest positioned Forever observation=data/(?:wowf|wow_classic_beta)/[0-9.]+/(?:npcs|trainers)\.json; record=' + ident, part):
                raise ValueError('unrecognized positioned trainer evidence: ' + ident)
            continue
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
            if row['faction'] != units.get(ident, ['', '', ''])[2] and not (access and not units.get(ident, ['', '', ''])[2]):
                raise ValueError('faction contradicts packaged units: ' + ident)
        elif basis == 'unknown':
            if row['faction'] and not access:
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
    refresh = json.loads(REFRESH_EVIDENCE.read_text())
    att = json.loads(ATT_EVIDENCE.read_text())
    if refresh['commit'] != REFRESH_PIN or att['commit'] != ATT_PIN:
        raise ValueError('trainer evidence commit mismatch')
    validate_records(refresh)
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
        access = access_proof(row, refresh, att, units)
        observed = any(url.startswith(SOURCE) for url in row['source'].split(' | '))
        is_fact = row['evidence'].startswith('NPC role facts;')
        licences = ' | '.join(dict.fromkeys(source_licence(url) for url in row['source'].split(' | ')))
        if is_fact:
            validate_fact_row(row, refresh, units)
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
            if row['faction'] != observed_faction(record, ident, units) and not (access and not observed_faction(record, ident, units)):
                raise ValueError('faction lacks pinned evidence: ' + str(ident))
        fresh_urls = [url for url in row['source'].split(' | ') if url.startswith(REFRESH_SOURCE)]
        if fresh_urls:
            current = refresh['npcs'].get(str(ident), {})
            paths = {v['path'] for v in current.values()}
            if any(url[len(REFRESH_SOURCE):] not in paths for url in fresh_urls):
                raise ValueError('unrecorded refresh evidence path: ' + str(ident))
            # A position record alone never establishes a role or access.
            title = current.get('title', {}).get('record', {}).get('title', '')
            if ('title=' + title + ';') in row['evidence']:
                interaction = trainer_window(current) or 'TradeskillTrainer' in current.get('npc', {}).get('record', {}).get('interactions', [])
                if classify(title, interaction, refresh['patterns']) != (kind, subkind):
                    raise ValueError('refresh title role lacks pinned corroboration: ' + str(ident))
                if row['faction'] != observed_faction(current, ident, units) and not (access and not observed_faction(current, ident, units)):
                    raise ValueError('refresh faction lacks pinned evidence: ' + str(ident))
            elif not is_fact and not observed and not any(url.startswith(SOURCE_PREFIXES[:2] + (ATT_SOURCE,)) for url in row['source'].split(' | ')):
                raise ValueError('position-only record lacks trainer role: ' + str(ident))
        att_urls = [url for url in row['source'].split(' | ') if url.startswith(ATT_SOURCE)]
        if att_urls:
            from urllib.parse import quote
            access_record = att.get('player_access', {}).get(str(ident), {})
            linked_url = ATT_SOURCE + quote(access_record.get('path', '')) + '#L' + str(access_record.get('line', ''))
            att_urls = [url for url in att_urls if url != linked_url]
        if att_urls:
            from urllib.parse import quote
            proof = att['npcs'].get(str(ident), {})
            expected_url = ATT_SOURCE + quote(proof.get('path', '')) + '#L' + str(proof.get('line', ''))
            if att_urls != [expected_url] or not re.search(r'\b' + str(ident) + r'\b', proof.get('literal', '')) or ('<' + proof.get('title', '') + '>') not in proof.get('literal', ''):
                raise ValueError('ATT literal source record mismatch: ' + str(ident))
            if classify(proof['title'], True) != (kind, subkind):
                raise ValueError('ATT title role mismatch: ' + str(ident))
            if 'rank_recipe' in proof:
                recipe = proof['rank_recipe']
                literal = proof['rank_node']['literal']
                spell = re.search(r'\br\(' + str(recipe['spell']) + r',\{([^{}]*)\}\)', literal)
                if not literal.startswith('n(' + str(ident) + ',{') or not spell or not re.search(r'\brank=' + str(recipe['rank']) + r'\b', spell[1]) or not re.search(r'\brequireSkill=' + str(PROFESSION_IDS[subkind]) + r'\b', spell[1]):
                    raise ValueError('ATT profession rank lacks literal recipe: ' + str(ident))
        if kind == 'profession' and not is_fact and not observed and not fresh_urls and not trainer_evidence(row['evidence'], subkind, row['rank']):
            raise ValueError('profession lacks trainer evidence: ' + str(ident))
        if not is_fact:
            validate_assertions(row, units, access)
        if row['faction'] not in ('', 'A', 'H', 'AH') or row['rank'] not in ('', 'apprentice', 'journeyman', 'expert', 'artisan') or row['has_position'] not in ('yes', 'no'):
            raise ValueError('invalid metadata: ' + str(ident))
        safe_name(row.get('name_enUS', ''))
        positions = position_list(row.get('positions', ''))
        mode = row.get('position_mode', 'fallback')
        if mode not in ('fallback', 'observed', 'att', 'emulator', 'player'):
            raise ValueError('unknown trainer position mode: ' + str(ident))
        if positions:
            if str(ident) in positioned and mode not in ('observed', 'player'):
                raise ValueError('trainer positions replace database positions: ' + str(ident))
            if mode == 'player':
                build, expected = player_positions(ident)
                proof = player_records()['npcs'].get(str(ident), {})
                if positions != expected or row['name_enUS'] != proof.get('name', ['', '', '', None])[3] or PLAYER_SOURCE not in row['source'].split(' | ') or ('player position; record=' + str(ident) + '; build=' + str(build)) not in row['evidence'].split(' | '):
                    raise ValueError('player positions lack pinned evidence/name: ' + str(ident))
                prior = refresh['npcs'].get(str(ident), {}).get('position')
                if prior and int(prior['path'].split('/')[2].split('.')[-1]) >= build:
                    raise ValueError('player position supersedes newer Forever evidence: ' + str(ident))
            elif mode == 'att':
                proof = att.get('access', {}).get(str(ident), {})
                literal = proof.get('literal', '')
                coord = re.search(r'coord = \{ ([0-9.]+), ([0-9.]+), MAP\.([A-Z_]+) \}', literal)
                with (ROOT / 'tools/fixtures/client/UiMap-1.60.1.70862-enUS.csv').open() as stream:
                    maps = {re.sub('[^A-Z]', '', r['Name_lang'].upper()): int(r['ID']) for r in csv.DictReader(stream) if r['Type'] == '3'}
                map_id = maps.get(coord[3].replace('_', '')) if coord else None
                expected = [(map_id, float(Decimal(coord[1]) / 100), float(Decimal(coord[2]) / 100))] if coord and map_id and re.search(r'qg = ' + str(ident) + r'\b', literal) else []
                if positions != expected or row['name_enUS'] != proof.get('name') or not att_urls:
                    raise ValueError('ATT positions lack pinned evidence/name: ' + str(ident))
            elif mode == 'emulator':
                if not is_fact or row['name_enUS']:
                    raise ValueError('emulator coordinates must contain facts only: ' + str(ident))
                allowed = emulator_positions(str(ident))
                if positions != allowed:
                    raise ValueError('emulator positions lack pinned evidence: ' + str(ident))
            else:
                record = (refresh if mode == 'observed' else records)['npcs'].get(str(ident), {})
                allowed = {(p['uiMap'], p['mapX'], p['mapY']) for p in record.get('position', {}).get('record', {}).get('positions', [])}
                pinned_name = record.get('title', {}).get('record', {}).get('name') or record.get('position', {}).get('record', {}).get('name')
                if not (fresh_urls if mode == 'observed' else observed) or not set(positions) <= allowed or not row.get('name_enUS') or row['name_enUS'] != pinned_name:
                    raise ValueError('trainer positions lack pinned evidence/name: ' + str(ident))
            if mode == 'observed':
                history = refresh['position_history'].get(str(ident), [])
                def chronology(ref):
                    product, build = ref['path'].split('/')[1:3]
                    return (ref['record'].get('lastSeen', ''), tuple(map(int, build.split('.'))), product == 'wowf', ref['path'].endswith('npcs.json'))
                if not history or record['position']['path'] != max(history, key=chronology)['path']:
                    raise ValueError('trainer position is not newest observation: ' + str(ident))
                latest = max(history, key=chronology)
                if record['position']['record'].get('positions') != latest['record'].get('positions') or record['position']['record'].get('lastSeen') != latest['record'].get('lastSeen'):
                    raise ValueError('trainer position differs from newest literal record: ' + str(ident))
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
        if row['kind'] not in ('class', 'profession', 'weapon', 'riding', 'pet'):
            continue
        if not row['faction']:
            continue
        key = 'trainer_' + row['kind'] + ('_' + row['subkind'] if row['subkind'] else '')
        groups[key].append(row['npc_id'] + ':' + row['faction'])
        if row.get('positions'):
            locations.append('\t'.join((row['npc_id'], row['name_enUS'], row['positions'], row.get('position_mode', 'fallback'))))
    lines = ['-- Generated by tools/build_trainers.py from tools/fixtures/trainers/trainers.tsv. Do not edit.',
             '-- Newest observed positions supersede shipped coordinates; personal learning/corrections win.',
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
