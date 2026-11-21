#!/usr/bin/env python3
"""Walled-city footprints from the client's own terrain area IDs.

Every ADT terrain chunk (MCNK, 33.3 yd square) records the AreaTable ID the
client assigns to that ground. Over a walled city's map rectangle, the
chunks whose area is the city (or one of its sub-areas) are its footprint;
the rest is the zone around it. Real routes uses this to tell whether a
point stored on a zone map inside a city's rectangle is inside the city or
outside it (Travel.lua's GoalPlace); near the edge it stays undecided.

Two steps:

  python3 tools/build_city_footprints.py --extract [--install DIR] [--product wowf]
      Reads the local client, offline and read-only (tools/verify_legs_casc.py),
      and writes tools/fixtures/travel/city-footprints.json: per city map, the
      chunk area IDs over its rectangle, with the build and every ADT's file
      ID and sha256. Record the fixture's sha256 in tools/fixtures/manifest.json.

  python3 tools/build_city_footprints.py [--check]
      Writes WaypointTracker/CityFootprints.lua from that pinned fixture and
      the pinned AreaTable (tools/fixtures/travel/AreaTable.csv). Needs no
      client. --check writes nothing and fails unless the shipped file matches.

The city maps, their rectangles and their area IDs are the pinned
UiMapAssignment rows (tools/fixtures/travel/UiMapAssignment.csv) of the
walled cities in TravelData.lua's cities block. Nothing is hand-entered: a
city whose terrain never carries its area (a city inside a world model, such
as Ironforge or Undercity) gets no footprint.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
TRAVEL = ROOT / 'tools/fixtures/travel'
FIXTURE = TRAVEL / 'city-footprints.json'
OUTPUT = ROOT / 'WaypointTracker/CityFootprints.lua'
TILE = 1600 / 3
CHUNK = TILE / 16
SCHEMA = 'wt-city-footprints-v1'


def cities():
    """The walled city maps, from TravelData.lua's generated cities block."""
    text = (ROOT / 'WaypointTracker/TravelData.lua').read_text()
    block = re.search(r'cities = \[\[\n(.*?)\]\]', text, re.S)
    if not block:
        raise SystemExit('TravelData.lua has no cities block')
    return sorted(int(line.split('\t')[0]) for line in block.group(1).splitlines() if line.strip())


def rectangles(maps):
    out = {}
    with (TRAVEL / 'UiMapAssignment.csv').open() as stream:
        for r in csv.DictReader(stream):
            m = int(r['UiMapID'])
            if m in maps and r['UiMin_0'] == '0' and r['UiMin_1'] == '0' and r['UiMax_0'] == '1' and r['UiMax_1'] == '1':
                if m in out:
                    raise SystemExit('two full-map assignments for map %d' % m)
                out[m] = dict(cont=int(r['MapID']), area=int(r['AreaID']),
                              x0=float(r['Region_0']), y0=float(r['Region_1']),
                              x1=float(r['Region_3']), y1=float(r['Region_4']))
    missing = [m for m in maps if m not in out]
    if missing:
        raise SystemExit('no UiMapAssignment rectangle for ' + ', '.join(map(str, missing)))
    return out


def chunk_range(r):
    """Global chunk indices covering the rectangle: gx along world Y, gy along world X."""
    gx0 = math.floor((32 * TILE - r['y1']) / CHUNK)
    gx1 = math.floor((32 * TILE - r['y0']) / CHUNK)
    gy0 = math.floor((32 * TILE - r['x1']) / CHUNK)
    gy1 = math.floor((32 * TILE - r['x0']) / CHUNK)
    return gx0, gx1, gy0, gy1


def extract(install, product):
    sys.path.insert(0, str(ROOT / 'tools'))
    from verify_legs_casc import LocalCASC, chunks, require
    casc = LocalCASC(install, product)
    with (TRAVEL / 'Map.csv').open() as stream:
        mapdb = {int(r['ID']): r for r in csv.DictReader(stream)}
    maps = cities()
    rects = rectangles(maps)
    wdts, adts, sources = {}, {}, {}

    def adt(cont, tx, ty):
        key = (cont, tx, ty)
        if key not in adts:
            if cont not in wdts:
                wdts[cont] = (int(mapdb[cont]['WdtFileDataID']),
                              dict(chunks(casc.file(int(mapdb[cont]['WdtFileDataID']), 'WDT'))))
            maid = wdts[cont][1].get('MAID', b'')
            require(len(maid) == 4096 * 32, 'WDT without modern MAID table')
            fid = struct.unpack_from('<8I', maid, (ty * 64 + tx) * 32)[0]
            areas = None
            if fid:
                raw = casc.file(fid, 'ADT-area-ids')
                sources['%d:%d:%d' % key] = dict(fid=fid, sha256=hashlib.sha256(raw).hexdigest())
                areas = {}
                for tag, data in chunks(raw):
                    if tag == 'MCNK':
                        ix, iy = struct.unpack_from('<2I', data, 4)
                        areas[ix, iy] = struct.unpack_from('<I', data, 52)[0]  # MCNK header areaId
                require(len(areas) == 256, 'incomplete ADT: expected 256 MCNKs')
            adts[key] = areas
        return adts[key]

    out = {}
    for m in maps:
        r = rects[m]
        gx0, gx1, gy0, gy1 = chunk_range(r)
        rows = []
        for gy in range(gy0, gy1 + 1):
            row = []
            for gx in range(gx0, gx1 + 1):
                areas = adt(r['cont'], gx // 16, gy // 16)
                row.append(areas[gx % 16, gy % 16] if areas is not None else None)
            rows.append(row)
        out[str(m)] = dict(cont=r['cont'], area=r['area'], gx=gx0, gy=gy0, rows=rows)
    fixture = dict(schema=SCHEMA, product=product,
                   build=casc.build.get('Version!STRING:0'), build_key=casc.build['Build Key!HEX:16'],
                   chunk_yards=CHUNK, source='ADT MCNK header areaId (offset 52), local client CASC, read-only',
                   wdt={str(c): v[0] for c, v in sorted(wdts.items())},
                   adt=dict(sorted(sources.items())), cities=out)
    FIXTURE.write_text(json.dumps(fixture, indent=1, sort_keys=True) + '\n')
    print('wrote %s (%s): %s' % (FIXTURE.relative_to(ROOT), fixture['build'],
                                 hashlib.sha256(FIXTURE.read_bytes()).hexdigest()))


def generate(check=False):
    fixture = json.loads(FIXTURE.read_text())
    if fixture.get('schema') != SCHEMA:
        raise SystemExit('unexpected footprint fixture schema')
    manifest = json.loads((ROOT / 'tools/fixtures/manifest.json').read_text())
    digest = hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
    entry = manifest.get('travel/city-footprints.json')
    if not entry or entry.get('sha256') != digest:
        raise SystemExit('tools/fixtures/manifest.json does not pin travel/city-footprints.json at ' + digest)
    with (TRAVEL / 'AreaTable.csv').open() as stream:
        parent = {int(r['ID']): int(r['ParentAreaID'] or 0) for r in csv.DictReader(stream)}

    def within(area, city):
        for _ in range(16):
            if area == city:
                return True
            if not area or area not in parent:
                return False
            area = parent[area]
        return False

    lines = [
        '-- Generated by tools/build_city_footprints.py from tools/fixtures/travel/city-footprints.json',
        '-- (client %s terrain area IDs; sha256 %s). Do not edit.' % (fixture['build'], digest),
        '-- Per walled city map: its terrain chunks (%.4f yd squares) over its map rectangle,' % fixture['chunk_yards'],
        '-- row by row (gy: world X, from the north), each "c" the city or one of its areas,',
        '-- "o" other ground, "?" no terrain. gx, gy: the first chunk (32 * 1600/3 - world / chunk).',
        '-- Cities whose terrain never carries their area (inside a world model) have none.',
        'local _, ns = ...',
        'ns.CityFootprints = {',
        '    build = "%s",' % fixture['build'],
        '    chunk = %r,' % fixture['chunk_yards'],
    ]
    summary = []
    for key in sorted(fixture['cities'], key=int):
        c = fixture['cities'][key]
        rows = [''.join('?' if a is None or a == 0 else ('c' if within(a, c['area']) else 'o') for a in row)
                for row in c['rows']]
        count = sum(row.count('c') for row in rows)
        summary.append('%s: %d city chunks of %d' % (key, count, sum(len(r) for r in rows)))
        if not count:
            lines.append('    -- %s: no terrain chunk carries area %d' % (key, c['area']))
            continue
        lines.append('    [%s] = { cont = %d, gx = %d, gy = %d, rows = {' % (key, c['cont'], c['gx'], c['gy']))
        lines.extend('        "%s",' % row for row in rows)
        lines.append('    } },')
    lines.append('}')
    text = '\n'.join(lines) + '\n'
    if check:
        if not OUTPUT.is_file() or OUTPUT.read_text() != text:
            raise SystemExit('FAIL %s is not what the pinned fixture generates' % OUTPUT.relative_to(ROOT))
        print('OK %s matches the pinned fixture: %s' % (OUTPUT.relative_to(ROOT), '; '.join(summary)))
        return
    OUTPUT.write_text(text)
    print('wrote %s: %s' % (OUTPUT.relative_to(ROOT), '; '.join(summary)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--extract', action='store_true', help='read the local client and write the pinned fixture')
    ap.add_argument('--check', action='store_true', help='fail unless the shipped Lua is what the pinned fixture generates')
    ap.add_argument('--install', default='/Applications/World of Warcraft', help='client install (has .build.info)')
    ap.add_argument('--product', default='wowf', help='CASC product (default: wowf)')
    a = ap.parse_args()
    if a.extract:
        extract(a.install, a.product)
    else:
        generate(check=a.check)


if __name__ == '__main__':
    main()
