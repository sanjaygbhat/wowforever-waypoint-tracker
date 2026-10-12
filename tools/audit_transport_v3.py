#!/usr/bin/env python3
"""Read-only build-70338 CASC taxi audit; writes only NEW analytical artifacts.

No network, game processes, SavedVariables or generator execution. DB2 layouts:
https://github.com/wowdev/WoWDBDefs/tree/master/definitions
https://github.com/wowdev/DBCD/blob/master/DBCD.IO/Readers/WDC5Reader.cs
Reuse verify_legs_casc.py without changes; no Blizzard binary files are exported.
"""
import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import struct

from verify_legs_casc import LocalCASC, require

TABLES = {
    'TaxiNodes': (1068100, 0x50D91A78, 0xE7B597F0, 4, [
        ('Name_lang', 's', 1), ('Pos', 'f', 3), ('MapOffset', 'f', 2),
        ('FlightMapOffset', 'f', 2), ('ID', 'i', 1), ('ContinentID', 'i', 1),
        ('ConditionID', 'i', 1), ('CharacterBitNumber', 'i', 1), ('Flags', 'i', 1),
        ('UiTextureKitID', 'i', 1), ('MinimapAtlasMemberID', 'i', 1),
        ('Facing', 'f', 1), ('SpecialIconConditionID', 'i', 1),
        ('VisibilityConditionID', 'i', 1), ('MountCreatureID', 'i', 2)]),
    'TaxiPath': (1067802, 0xAB30A45C, 0xA303DE51, 0, [
        ('ID', 'i', 1), ('FromTaxiNode', 'i', 1), ('ToTaxiNode', 'i', 1), ('Cost', 'i', 1)]),
    'TaxiPathNode': (1000437, 0xE5E988BC, 0xFE362E70, 1, [
        ('Loc', 'f', 3), ('ID', 'i', 1), ('PathID', 'i', 1), ('NodeIndex', 'i', 1),
        ('ContinentID', 'i', 1), ('Flags', 'i', 1), ('Delay', 'i', 1),
        ('ArrivalEventID', 'i', 1), ('DepartureEventID', 'i', 1)])}


def bits(raw, start, size):
    require(0 <= start and 0 <= size <= 96 and start + size <= len(raw) * 8,
            'field outside record')
    return (int.from_bytes(raw, 'little') >> start) & ((1 << size) - 1)


def decode_wdc5(raw, definition, relation_name=None):
    """Deliberately narrow decoder: one non-sparse, unencrypted, inline-ID section.

    Rejects unknown layouts, copies, sparse data, mixed sections and truncation.
    All columns (including common/pallet/array/float/string) are decoded, then
    independently compared against every cached CSV cell by the caller.
    """
    _, table_hash, layout_hash, id_column, columns = definition
    require(len(raw) >= 244 and raw[:4] == b'WDC5', 'requires WDC5')
    require(struct.unpack_from('<I', raw, 4)[0] == 5, 'requires schema version 5')
    h = struct.unpack_from('<9I2H7I', raw, 136)
    count, fields, record_size, strings, table, layout, low, high, locale = h[:9]
    flags, id_index, total, packed, lookup, meta_bytes, common_bytes, pallet_bytes, sections = h[9:]
    require(table == table_hash and layout == layout_hash, 'unrecognized table/layout')
    require(fields == total == len(columns) and meta_bytes == 24 * fields,
            'unexpected field metadata')
    external_id = id_column is None
    require(flags == (4 if external_id else 0) and id_index == (0 if external_id else id_column) and sections == 1,
            'unsupported sparse/external-ID/multi-section table')
    key, offset, rows, section_strings, record_end, id_bytes, relation_bytes, sparse, copies = \
        struct.unpack_from('<Q8I', raw, 204)
    require(key == record_end == sparse == copies == 0 and id_bytes == (4 * count if external_id else 0) and rows == count
            and strings == section_strings, 'unsupported section')
    field_meta = [struct.unpack_from('<hH', raw, 244 + 4 * i) for i in range(fields)]
    start = 244 + 4 * fields
    metas = [struct.unpack_from('<HHIIIII', raw, start + 24 * i) for i in range(fields)]
    pos = start + 24 * fields
    pallets, commons = {}, {}
    for mode in (3, 4):
        for i, (_, _, extra, compression, _, _, _) in enumerate(metas):
            if compression == mode:
                require(extra % 4 == 0 and pos + extra <= len(raw), 'bad pallet bounds')
                pallets[i] = struct.unpack_from('<%dI' % (extra // 4), raw, pos)
                pos += extra
    require(pos == start + meta_bytes + pallet_bytes, 'pallet size mismatch')
    for i, (_, _, extra, compression, _, _, _) in enumerate(metas):
        if compression == 2:
            require(extra % 8 == 0 and pos + extra <= len(raw), 'bad common bounds')
            commons[i] = dict(struct.unpack_from('<II', raw, p) for p in range(pos, pos + extra, 8))
            pos += extra
    require(pos == offset and pos == start + meta_bytes + pallet_bytes + common_bytes,
            'metadata/records boundary mismatch')
    string_start = offset + count * record_size
    require(string_start + strings + id_bytes + relation_bytes == len(raw), 'section/file bounds mismatch')
    external_ids = struct.unpack_from('<%dI' % count, raw, string_start + strings) if external_id else None
    relations = {}
    if relation_bytes:
        p = string_start + strings + id_bytes
        n, minimum, maximum = struct.unpack_from('<III', raw, p)
        require(relation_bytes == 12 + 8 * n, 'bad relationship bounds')
        require(all(struct.unpack_from('<II', raw, p + 12 + 8 * k)[1] < count for k in range(n)),
                'relationship row outside section')
        relations = {index: parent for parent,index in
                     (struct.unpack_from('<II', raw, p + 12 + 8 * k) for k in range(n))}
    result = []
    for row_index in range(count):
        record_pos = offset + row_index * record_size
        record = raw[record_pos:record_pos + record_size]
        def values(i, row_id=0):
            bit_offset, bit_size, extra, mode, default, width, cardinality = metas[i]
            name, kind, arity = columns[i]
            if mode == 0:
                cell_width = 32 - field_meta[i][0]
                require(cell_width > 0 and bit_size == arity * cell_width, 'bad uncompressed width')
                v = [bits(record, bit_offset + k * cell_width, cell_width) for k in range(arity)]
            elif mode in (1, 5):
                require(arity == 1 and bit_size == width, 'bad immediate width')
                value = bits(record, bit_offset, width)
                if mode == 5 and value & (1 << (width - 1)):
                    value -= 1 << width
                v = [value]
            elif mode == 2:
                require(arity == 1 and bit_size == 0, 'bad common column')
                v = [commons[i].get(row_id, default)]
            elif mode in (3, 4):
                index = bits(record, bit_offset, width)
                size = cardinality if mode == 4 else 1
                require(arity == size and (index + 1) * size <= len(pallets[i]), 'bad pallet index')
                v = list(pallets[i][index * size:(index + 1) * size])
            else:
                raise ValueError('unsupported compression ' + str(mode))
            if kind == 'f':
                v = [struct.unpack('<f', struct.pack('<I', x))[0] for x in v]
                require(all(math.isfinite(x) for x in v), 'nonfinite coordinate')
            elif kind == 's':
                if v[0] == 0:
                    return ['']
                pointer = record_pos + bit_offset // 8 + v[0]
                require(string_start <= pointer < string_start + strings, 'bad string pointer')
                end = raw.find(b'\0', pointer, string_start + strings)
                require(end >= pointer, 'unterminated string')
                v = [raw[pointer:end].decode('utf-8')]
            return v
        row_id = external_ids[row_index] if external_id else values(id_column)[0]
        require(low <= row_id <= high, 'ID out of range')
        row = {'ID': row_id} if external_id else {}
        for i, (name, _, arity) in enumerate(columns):
            v = values(i, row_id)
            if arity == 1:
                row[name] = v[0]
            else:
                row.update({name + '_' + str(k): x for k, x in enumerate(v)})
        if relation_name:
            require(row_index in relations, 'missing external relationship')
            row[relation_name] = relations[row_index]
        result.append(row)
    require(len({r['ID'] for r in result}) == count, 'duplicate IDs')
    return result


def compare_csv(rows, raw):
    cached = list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))))
    expected = {int(r['ID']): r for r in cached}
    require(set(expected) == {r['ID'] for r in rows}, 'CASC/cache ID mismatch')
    checked = 0
    for row in rows:
        require(set(row) == set(expected[row['ID']]), 'CASC/cache columns differ')
        for key, value in row.items():
            other = expected[row['ID']][key]
            okay = (abs(value - float(other)) <= max(1e-8, abs(value) * 1e-12)
                    if isinstance(value, float) else value == (int(other) if isinstance(value, int) else other))
            require(okay, 'CASC/cache mismatch: %s %s' % (row['ID'], key))
            checked += 1
    return checked


def lua_rows(raw, block):
    match = re.search(r'\b' + re.escape(block) + r'\s*=\s*\[\[(.*?)\]\]', raw, re.S)
    require(match is not None, 'missing Lua data block ' + block)
    return [line.split('\t') for line in match[1].splitlines() if line.strip()]


def chord_length(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def catmull_length(points, subdivisions=64):
    """Uniform Catmull-Rom sensitivity model, reflected end controls.

    No claim Blizzard uses these endpoint controls or these exact nodes.
    Never join maps/teleports. Compare 32/64 sampling for numerical stability.
    """
    if len(points) < 2:
        return 0.0
    reflect = lambda a, b: tuple(2 * x - y for x, y in zip(a, b))
    controls = [reflect(points[0], points[1]), *points, reflect(points[-1], points[-2])]
    length = 0.0
    for index in range(1, len(controls) - 2):
        p0, p1, p2, p3 = controls[index - 1:index + 3]
        previous = p1
        for k in range(1, subdivisions + 1):
            t = k / subdivisions
            current = tuple(0.5 * (2*b + (-a+c)*t + (2*a-5*b+4*c-d)*t*t
                                  + (-a+3*b-3*c+d)*t*t*t) for a,b,c,d in zip(p0,p1,p2,p3))
            length += math.dist(previous, current)
            previous = current
    return length


def analyze(install, repo):
    casc = LocalCASC(install)
    require(casc.build['Version!STRING:0'] == '1.60.1.70338', 'this audit requires build 70338')
    tables, cache_hashes, cells = {}, {}, {}
    for name, definition in TABLES.items():
        tables[name] = decode_wdc5(casc.file(definition[0], name), definition)
        raw = (repo / 'tools/.cache/travel' / (name + '.csv')).read_bytes()
        cache_hashes[name] = hashlib.sha256(raw).hexdigest()
        cells[name] = compare_csv(tables[name], raw)
    taxi = {r['ID']: r for r in tables['TaxiNodes']}
    points = {}
    for row in tables['TaxiPathNode']:
        points.setdefault(row['PathID'], []).append(row)
    travel_raw = (repo / 'WaypointTracker/TravelData.lua').read_bytes()
    travel = travel_raw.decode()
    links = lua_rows(travel, 'links')
    nodes = {r[0]: r for r in lua_rows(travel, 'nodes')}
    taxi_links = {(int(r[0][5:]), int(r[1][5:])): r for r in links if r[2] == 'taxi'}
    fare_rows = lua_rows(travel, 'taxiFares') if re.search(r'\btaxiFares\s*=', travel) else []
    fares = {(int(r[0][5:]), int(r[1][5:])): int(r[2]) for r in fare_rows}
    flight_results, services, stops = [], [], []
    for path in tables['TaxiPath']:
        pid, a, b = path['ID'], path['FromTaxiNode'], path['ToTaxiNode']
        ps = sorted(points.get(pid, []), key=lambda x: x['NodeIndex'])
        require(not ps or [p['NodeIndex'] for p in ps] == list(range(len(ps))), 'noncontiguous path')
        same_map = bool(ps) and len({p['ContinentID'] for p in ps}) == 1
        geometry = [tuple(p['Loc_' + str(k)] for k in range(3)) for p in ps]
        chord = chord_length(geometry) if same_map else None
        link = taxi_links.get((a, b))
        if link:
            require(chord is not None and len(ps) > 1, 'shipped taxi missing continuous geometry')
            curve32, curve64 = catmull_length(geometry, 32), catmull_length(geometry, 64)
            flight_results.append(dict(path_id=pid, from_id=a, to_id=b, base_fare_copper=path['Cost'],
                fare_preserved=fares.get((a,b)) == path['Cost'], node_count=len(ps), chord_yards=chord,
                curve_model_yards=curve64, curve_sampling_delta_yards=abs(curve64-curve32),
                chord_seconds_at30=chord/30, curve_seconds_at30=curve64/30,
                chord_seconds_at32=chord/32, curve_seconds_at32=curve64/32,
                chord_seconds_at36=chord/36, shipped_seconds=float(link[3]),
                dialogue=len(link) > 11 and link[11] == '1', measured=False))
        if a in (62,63,84,3205,3274) or any(p['Delay'] or p['Flags'] & 1 for p in ps) or not (a and b):
            services.append(dict(path_id=pid, from_id=a, to_id=b, base_fare_copper=path['Cost'],
                point_count=len(ps), maps=sorted({p['ContinentID'] for p in ps}),
                delay_values=sorted({p['Delay'] for p in ps}), flags=sorted({p['Flags'] for p in ps}),
                chord_seconds_at30=chord/30 if chord is not None else None))
        for p in ps:
            if not p['Delay']:
                continue
            nearest = []
            for nid, n in nodes.items():
                if n[1] not in ('dock','zeppelin','tram','portal') or int(n[3]) != p['ContinentID']:
                    continue
                distance = math.hypot(float(n[4])-p['Loc_0'], float(n[5])-p['Loc_1'])
                nearest.append((distance,nid))
            nearest.sort()
            stops.append(dict(path_id=pid, index=p['NodeIndex'], continent=p['ContinentID'],
                x=p['Loc_0'],y=p['Loc_1'],z=p['Loc_2'],delay=p['Delay'],flags=p['Flags'],
                arrival_event=p['ArrivalEventID'], departure_event=p['DepartureEventID'],
                nearest_endpoints=[dict(id=nid,horizontal_yards=dist) for dist,nid in nearest[:3]]))
    uncertain_nodes = []
    for tid in (3205,3274,62,63,84,85,86,87):
        n = taxi[tid]
        uncertain_nodes.append(dict(n, outgoing=[p['ID'] for p in tables['TaxiPath'] if p['FromTaxiNode']==tid],
                                    incoming=[p['ID'] for p in tables['TaxiPath'] if p['ToTaxiNode']==tid]))
    return dict(build=casc.build, casc_files=casc.manifest, cache_sha256=cache_hashes,
                csv_cells_verified=cells, table_rows={k:len(v) for k,v in tables.items()},
                travel_sha256=hashlib.sha256(travel_raw).hexdigest(), flight_models=flight_results,
                special_paths=services, transport_stops=stops, uncertain_nodes=uncertain_nodes,
                notes=['All seconds are geometric models; baseline server speed is unresolved.',
                       '30 yd/s is current addon assumption; 32 yd/s is an emulator comparison.',
                       '36 yd/s assumes 30 baseline and +20% speed, not a confirmed perk multiplier.',
                       'Catmull-Rom endpoint controls and server node trimming are unresolved.',
                       'Delay units/transport speed require transport template/server evidence.',
                       'Stop coordinates are moving vehicle anchors, not walkable boarding coordinates.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', type=Path, default=Path('/Applications/World of Warcraft'))
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--timings', type=Path)
    args = parser.parse_args()
    outputs = [p for p in (args.evidence,args.timings) if p is not None]
    require(len(set(outputs)) == len(outputs), 'outputs must differ')
    require(all(not p.exists() for p in outputs), 'refusing to overwrite an existing file')
    evidence = analyze(args.install,args.repo)
    if args.evidence:
        with args.evidence.open('x') as stream:
            json.dump(evidence,stream,indent=2);stream.write('\n')
    if args.timings:
        with args.timings.open('x',newline='') as stream:
            rows=evidence['flight_models']
            writer=csv.DictWriter(stream,fieldnames=list(rows[0]),delimiter='\t')
            writer.writeheader();writer.writerows(rows)
    print(json.dumps(dict(build=evidence['build']['Version!STRING:0'],
                          rows=evidence['table_rows'], cells=evidence['csv_cells_verified'],
                          flights=len(evidence['flight_models']), stops=len(evidence['transport_stops']),
                          fares_preserved=sum(r['fare_preserved'] for r in evidence['flight_models']),
                          max_curve_sampling_delta_yards=max(r['curve_sampling_delta_yards'] for r in evidence['flight_models'])),indent=2))


if __name__ == '__main__':
    main()
