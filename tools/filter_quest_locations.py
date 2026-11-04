#!/usr/bin/env python3
"""Remove approved unresolved positions after generation; preserve all identities."""
import csv
import json
import re
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def filtered(text, removals):
    count, lines = 0, []
    for line in text.splitlines(keepends=True):
        fields = line.rstrip('\n').split('\t')
        key = fields[0] + fields[1] if len(fields) > 1 else ''
        if key not in removals:
            lines.append(line)
            continue
        index = 6 if fields[0] == 'N' else 3
        sections = []
        for section in fields[index].split(';'):
            if not section:
                continue
            mid, coords = section.split(':')
            coords = coords.split(','); kept = []
            assert len(coords) % 2 == 0, 'invalid position pairs: ' + key
            for x,y in zip(coords[::2], coords[1::2]):
                if (int(mid), Decimal(x), Decimal(y)) in removals[key]:
                    count += 1
                else:
                    kept.extend([x,y])
            if kept:
                sections.append(mid + ':' + ','.join(kept))
        fields[index] = ';'.join(sections)
        lines.append('\t'.join(fields) + ('\n' if line.endswith('\n') else ''))
    return ''.join(lines), count


def removal_inputs():
    grouped = defaultdict(lambda: defaultdict(set))
    with (ROOT/'docs/quest-location-verdicts.tsv').open() as f:
        rows = [r for r in csv.DictReader(f, delimiter='\t') if r['verdict'] == 'UNRESOLVED']
    assert len(rows) == 232, 'approved unresolved inventory changed'
    for r in rows:
        mid, xy = r['current'].split(':'); x,y = xy.split(',')
        assert r['record'][0] in ('N','O'), 'position-only NPC/object removal required'
        grouped[r['file']][r['record']].add((int(mid), Decimal(x)*10, Decimal(y)*10))
    return grouped


def main():
    total = 0
    outputs = []
    for name, removals in removal_inputs().items():
        path = ROOT/'WaypointTracker_Data'/name
        text, count = filtered(path.read_text(), removals)
        if name == 'Curated.lua':
            policy = json.loads((ROOT/'tools/fixtures/travel/verified-routing.json').read_text())
            for objective in policy['quest_objectives']:
                point = '%s:%s,%s' % (objective['map'], int(objective['x']*10), int(objective['y']*10))
                pattern = r'(?m)^N\t' + str(objective['npc']) + r'\t([^\n]*)$'
                existing = re.search(pattern, text)
                if existing:
                    fields = existing[0].split('\t'); fields[6] = point
                    text = text[:existing.start()] + '\t'.join(fields) + text[existing.end():]
                else:
                    row = '\t'.join(['N', str(objective['npc']), objective['name'], '', '', '', point, '']) + '\n'
                    end = text.index(']==]')
                    text = text[:end] + row + text[end:]
        outputs.append((path, text)); total += count
    assert total in (0,232), 'stale or partially applied unresolved locations: ' + str(total)
    for path,text in outputs:
        path.write_text(text)
    print('Removed %d unresolved positions; identities preserved; verified objective curation applied' % total)


if __name__ == '__main__':
    main()
