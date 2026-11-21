#!/usr/bin/env python3
"""City footprints: the shipped CityFootprints.lua is exactly what the pinned
fixture generates (tools/build_city_footprints.py --check), the fixture is
pinned in the manifest, and its provenance is complete."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
fixture_path = ROOT / 'tools/fixtures/travel/city-footprints.json'
fixture = json.loads(fixture_path.read_text())
manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
failed = 0


def check(ok, message):
    global failed
    print(('PASS: ' if ok else 'FAIL: ') + message)
    failed += 0 if ok else 1


entry = manifest.get('travel/city-footprints.json', {})
check(entry.get('sha256') == hashlib.sha256(fixture_path.read_bytes()).hexdigest(), 'the manifest pins the footprint fixture')
check(fixture.get('build') and fixture['build'] in entry.get('source', '') and fixture.get('build_key') in entry.get('source', ''),
      'the manifest names the client build and build key the fixture was read from')
check(fixture.get('schema') == 'wt-city-footprints-v1' and fixture.get('wdt') and fixture.get('adt'),
      'the fixture records its schema, WDT and every ADT read')
check(all(len(v.get('sha256', '')) == 64 and v.get('fid') for v in fixture['adt'].values()), 'every ADT read has its file ID and sha256')
check(sorted(fixture['cities'], key=int) == ['1453', '1454', '1455', '1456', '1457', '1458'], 'all six walled cities were read')
for key, c in fixture['cities'].items():
    widths = {len(r) for r in c['rows']}
    check(len(widths) == 1 and c['rows'], 'city %s: a rectangular chunk grid' % key)
    seen = {a for r in c['rows'] for a in r}
    check(None not in seen, 'city %s: terrain everywhere in its rectangle' % key)
result = subprocess.run([sys.executable, '-B', 'tools/build_city_footprints.py', '--check'], cwd=ROOT, capture_output=True, text=True)
print(result.stdout.strip())
check(result.returncode == 0, 'CityFootprints.lua is regenerated exactly from the pinned fixture' + (': ' + result.stderr.strip() if result.returncode else ''))
print('City footprints: %d failed' % failed)
sys.exit(1 if failed else 0)
