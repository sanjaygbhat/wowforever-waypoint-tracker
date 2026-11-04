#!/usr/bin/env python3
"""Verify route chords from the installed build's terrain; writes NEW artifacts.

python3 tools/verify_legs_terrain.py --output docs/terrain-leg-evidence.json
Optional --replacements runs bounded A* for blocked chords (candidate paths,
never silently claimed to be collision-complete). No network, game, writes to
client/WTF, Lua execution, or third-party packages. See terrain-report.md.

ADT/WDT/M2 wire references: MIT wow.export loaders at
https://github.com/Marlamin/wow.export/tree/main/src/js/3D/loaders
No upstream implementation or raw client assets are bundled.
"""
import argparse
from array import array
from collections import Counter, deque
import csv
from functools import lru_cache
import hashlib
import heapq
import json
import math
from pathlib import Path
import re
import struct
import sys
import time

from verify_legs_casc import EvidenceUnavailable, LocalCASC, chunks, require

ROOT = Path(__file__).resolve().parents[1]
TILE = 1600 / 3
CHUNK = TILE / 16
UNIT = CHUNK / 8
ORIGIN = 32 * TILE
DIRS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
MARGIN = 0.75


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_rows(path):
    with Path(path).open() as stream:
        return list(csv.DictReader(stream, delimiter='\t'))


def tsv_block(text, name):
    m = re.search(r'\b' + name + r'\s*=\s*\[\[\n(.*?)\n\]\]', text, re.S)
    require(m is not None, 'missing TravelData block ' + name)
    return [s.split('\t') for s in m[1].splitlines() if s]


def load_inputs():
    data = (ROOT / 'WaypointTracker/TravelData.lua').read_text()
    nodes = {}
    for row in tsv_block(data, 'nodes'):
        nodes[row[0]] = dict(id=row[0], kind=row[1], area=int(row[2]), cont=int(row[3]),
                             wx=float(row[4]), wy=float(row[5]), map=int(row[6]),
                             x=float(row[7]), y=float(row[8]))
    with (ROOT / 'tools/fixtures/travel/UiMapAssignment.csv').open() as stream:
        maps = {int(r['UiMapID']): r for r in csv.DictReader(stream)
                if r['UiMin_0'] == '0' and r['UiMax_0'] == '1'}

    def point(mid, x, y, name):
        r = maps[mid]
        wx = float(r['Region_3']) - y / 100 * (float(r['Region_3']) - float(r['Region_0']))
        wy = float(r['Region_4']) - x / 100 * (float(r['Region_4']) - float(r['Region_1']))
        return dict(id=name, cont=int(r['MapID']), wx=wx, wy=wy, map=mid, x=x, y=y)

    legs = []
    for row in read_rows(ROOT / 'docs/data-walking-review.tsv'):
        legs.append(dict(id=row['from'] + '>' + row['to'], kind='review-leg',
                         a=nodes[row['from']], b=nodes[row['to']], review=row))
    require(len(legs) == 137 and len({r['id'] for r in legs}) == 137,
            'expected the original 137 directed review legs')
    # Treat a barrier as a geometric assertion, not a walk along its axis.
    barriers = []
    for i, row in enumerate(tsv_block(data, 'barriers'), 1):
        mid = int(row[0]); coords = list(map(float, row[1:5]))
        a = point(mid, coords[0], coords[1], 'barrier-%d-start' % i)
        b = point(mid, coords[2], coords[3], 'barrier-%d-end' % i)
        barriers.append(dict(id='barrier-%d' % i, map=mid, a=a, b=b))
        for j in range(11):
            t = j / 10
            wx = a['wx'] + t * (b['wx'] - a['wx'])
            wy = a['wy'] + t * (b['wy'] - a['wy'])
            dx, dy = b['wx'] - a['wx'], b['wy'] - a['wy']
            length = math.hypot(dx, dy)
            nx, ny = -dy / length * 40, dx / length * 40
            pa = dict(a, id='barrier-%d-probe-%d-a' % (i, j), wx=wx - nx, wy=wy - ny)
            pb = dict(a, id='barrier-%d-probe-%d-b' % (i, j), wx=wx + nx, wy=wy + ny)
            legs.append(dict(id='barrier-%d-crossing-%02d' % (i, j), kind='barrier-crossing', a=pa, b=pb))
    road = nodes['ROAD_HILLSBRAD_DARROW_WEST']
    legs.append(dict(id='ROAD_HILLSBRAD_DARROW_WEST-footprint', kind='road-point', a=road, b=road))
    for name in ['ROAD_HILLSBRAD_TARREN_JUNCTION', 'TAXI_13', 'TAXI_14',
                 'BORDER_HILLSBRAD_FOOTHILLS_TO_ALTERAC_MOUNTAINS',
                 'BORDER_HILLSBRAD_FOOTHILLS_TO_ALTERAC_MOUNTAINS_DALARAN']:
        if name in nodes:
            legs.append(dict(id=road['id'] + '>' + name, kind='road-approach', a=road, b=nodes[name]))
    return legs, barriers, maps


def plane(tri, u, v):
    """Triangle height and surface inclination; u/v are in yard units."""
    (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = tri
    det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    gx = ((z1 - z0) * (y2 - y0) - (z2 - z0) * (y1 - y0)) / det
    gy = ((x1 - x0) * (z2 - z0) - (x2 - x0) * (z1 - z0)) / det
    return z0 + gx * (u - x0) + gy * (v - y0), math.degrees(math.atan(math.hypot(gx, gy)))


class TileTerrain:
    def __init__(self, raw, fid, tx, ty):
        self.fid = fid
        self.chunks = {}
        self.liquid = None
        self.unknown_chunks = []
        for tag, data in chunks(raw):
            if tag == 'MVER':
                require(struct.unpack('<I', data)[0] == 18, 'unsupported ADT version')
            elif tag == 'MH2O':
                self.liquid = data
            elif tag == 'MCNK':
                flags, ix, iy = struct.unpack_from('<3I', data)
                px, py, pz = struct.unpack_from('<3f', data, 104)
                require(abs(px - ((32 - ty) * TILE - iy * CHUNK)) < .02
                        and abs(py - ((32 - tx) * TILE - ix * CHUNK)) < .02,
                        'ADT / world axis registration mismatch')
                nested = dict(chunks(data[128:]))
                require(len(nested.get('MCVT', b'')) == 145 * 4, 'missing terrain height grid')
                heights = array('f')
                heights.frombytes(nested['MCVT'])
                if sys.byteorder != 'little':
                    heights.byteswap()
                require(all(math.isfinite(h) and abs(h) < 100000 for h in heights), 'invalid heights')
                self.chunks[ix, iy] = dict(flags=flags, ix=ix, iy=iy, px=px, py=py, pz=pz,
                                          heights=heights, high=data[20:28],
                                          low=struct.unpack_from('<H', data, 60)[0],
                                          legacy_liquid='MCLQ' in nested)
            elif tag not in {'MHDR', 'MFBO', 'MTXF'}:
                self.unknown_chunks.append(tag)
        require(len(self.chunks) == 256, 'incomplete ADT: expected 256 MCNKs')
        self.water = self.parse_water()

    def parse_water(self):
        """Use existence masks and declared min/max, avoiding format guesses.

        The declared range supplies a conservative depth lower bound even for
        unfamiliar liquid vertex formats. Nonconstant ranges remain uncertain.
        """
        out = {}
        if not self.liquid:
            return out
        require(len(self.liquid) >= 256 * 12, 'truncated MH2O')
        for i in range(256):
            pos, count, attrs = struct.unpack_from('<3I', self.liquid, i * 12)
            require(count < 100 and pos + count * 24 <= len(self.liquid), 'invalid MH2O instances')
            layers = []
            for j in range(count):
                typ, obj, low, high, x, y, w, h, bitmap, vertices = struct.unpack_from(
                    '<HHff4BII', self.liquid, pos + j * 24)
                # liquidObject IDs <=41 describe full chunk dimensions in modern ADTs.
                if obj <= 41:
                    x, y, w, h = 0, 0, 8, 8
                require(w <= 8 and h <= 8 and x + w <= 8 and y + h <= 8
                        and math.isfinite(low) and math.isfinite(high) and low <= high + .01,
                        'unsupported MH2O dimensions/range')
                n = (w * h + 7) // 8
                require(bitmap == 0 or bitmap + n <= len(self.liquid), 'truncated water bitmap')
                mask = int.from_bytes(self.liquid[bitmap:bitmap + n], 'little') if bitmap else (1 << (w*h)) - 1
                layers.append(dict(type=typ, object=obj, low=low, high=high,
                                   x=x, y=y, w=w, h=h, mask=mask))
            if layers:
                out[i] = layers
        return out

    def sample(self, wx, wy):
        # MCNK indexX runs along world Y; indexY along world X.
        first = self.chunks[0, 0]
        ix = min(15, max(0, math.floor((first['py'] - wy) / CHUNK)))
        iy = min(15, max(0, math.floor((first['px'] - wx) / CHUNK)))
        c = self.chunks[ix, iy]
        u = min(8 - 1e-7, max(0, (c['py'] - wy) / UNIT))
        v = min(8 - 1e-7, max(0, (c['px'] - wx) / UNIT))
        col, row = math.floor(u), math.floor(v)
        fu, fv = u - col, v - row
        outer = row * 17 + col
        hs = c['heights']
        tl = (0, 0, hs[outer] + c['pz'])
        tr = (UNIT, 0, hs[outer + 1] + c['pz'])
        bl = (0, UNIT, hs[outer + 17] + c['pz'])
        br = (UNIT, UNIT, hs[outer + 18] + c['pz'])
        center = (UNIT / 2, UNIT / 2, hs[outer + 9] + c['pz'])
        if fv <= fu and fv <= 1 - fu:
            tri, ti = (tl, tr, center), 0
        elif fu >= fv and fu >= 1 - fv:
            tri, ti = (tr, br, center), 1
        elif fv >= fu and fv >= 1 - fu:
            tri, ti = (br, bl, center), 2
        else:
            tri, ti = (bl, tl, center), 3
        z, slope = plane(tri, fu * UNIT, fv * UNIT)
        hole = bool((c['high'][row] >> col) & 1) if c['flags'] & 0x10000 else bool(
            c['low'] & (1 << (row // 2 * 4 + col // 2)))
        liquids = []
        for layer in self.water.get(iy * 16 + ix, []):
            x, y = col - layer['x'], row - layer['y']
            if 0 <= x < layer['w'] and 0 <= y < layer['h'] and layer['mask'] & (1 << (y * layer['w'] + x)):
                liquids.append(dict(type=layer['type'], min_depth=layer['low'] - z,
                                    max_depth=layer['high'] - z))
        return dict(z=z, slope=slope, hole=hole, liquids=liquids,
                    terrain_fdid=self.fid, chunk=[ix, iy], cell=[col, row], triangle=ti,
                    unknown=bool(self.unknown_chunks or c['legacy_liquid']))


class World:
    def __init__(self, casc):
        self.casc = casc
        with (ROOT / 'tools/fixtures/travel/Map.csv').open() as stream:
            self.mapdb = {int(r['ID']): r for r in csv.DictReader(stream)}
        self.wdts = {}
        self.tiles = {}
        self.models = {}
        self.obstacles = {}
        self.obstacle_bins = {}
        self.registered_objects = set()
        self.unknown_object_tiles = set()
        self.loaded_rings = {}
        self.errors = {}

    def wdt(self, cont):
        if cont not in self.wdts:
            fid = int(self.mapdb[cont]['WdtFileDataID'])
            d = dict(chunks(self.casc.file(fid, 'WDT')))
            require(len(d.get('MAID', b'')) == 4096 * 32, 'WDT without modern MAID table')
            self.wdts[cont] = d
        return self.wdts[cont]

    def model_radius(self, fid):
        if fid not in self.models:
            try:
                raw = self.casc.file(fid, 'M2-collision-bounds')
                if raw[:4] == b'MD21':
                    raw = dict(chunks(raw, reverse=False))['MD21']
                require(raw[:4] == b'MD20', 'unsupported M2 wrapper')
                box = struct.unpack_from('<7f', raw, 188)
                indices, _, positions, _, _, _ = struct.unpack_from('<6I', raw, 216)
                if not indices or not positions:
                    self.models[fid] = (0, 0, False)
                else:
                    require(all(math.isfinite(v) and abs(v) < 100000 for v in box), 'invalid M2 bounds')
                    xy = math.hypot(max(abs(box[0]), abs(box[3])), max(abs(box[1]), abs(box[4])))
                    xyz = math.hypot(xy, max(abs(box[2]), abs(box[5])))
                    self.models[fid] = (xy, xyz, False)
            except (EvidenceUnavailable, KeyError, struct.error) as exc:
                self.errors['model-' + str(fid)] = str(exc)
                self.models[fid] = (200, 200, True)  # Unknown bounds invalidate tile, not a guessed clear radius.
        return self.models[fid]

    def tile(self, cont, tx, ty):
        key = (cont, tx, ty)
        if key not in self.tiles:
            try:
                require(0 <= tx < 64 and 0 <= ty < 64, 'outside WDT')
                wdt = self.wdt(cont)
                fields = struct.unpack_from('<8I', wdt['MAID'], (ty * 64 + tx) * 32)
                rootid, objid = fields[:2]
                require(rootid != 0 and objid != 0, 'missing terrain/object tile')
                terrain = TileTerrain(self.casc.file(rootid, 'ADT-height-liquid-holes'), rootid, tx, ty)
                raw = self.casc.file(objid, 'ADT-object-placements')
                obj = dict(chunks(raw))
                unhandled=set(obj) - {'MVER', 'MDDF', 'MODF', 'MCNK', 'MWDS', 'MMDX', 'MMID', 'MWMO', 'MWID'}
                require(not unhandled, 'unknown object placement chunk: ' + ','.join(sorted(unhandled)))
                obstacles = []
                for pos in range(0, len(obj.get('MODF', b'')), 64):
                    vals = struct.unpack_from('<II12f4H', obj['MODF'], pos)
                    lower, upper = vals[8:11], vals[11:14]
                    require(all(math.isfinite(v) for v in lower + upper), 'invalid WMO bounds')
                    # MODF uses positive editor coordinates: X -> world Y, Z -> world X.
                    obstacles.append(dict(type='WMO', fdid=vals[0], uid=vals[1],
                                          bounds=[ORIGIN - max(lower[2], upper[2]) - MARGIN,
                                                  ORIGIN - max(lower[0], upper[0]) - MARGIN,
                                                  ORIGIN - min(lower[2], upper[2]) + MARGIN,
                                                  ORIGIN - min(lower[0], upper[0]) + MARGIN]))
                for pos in range(0, len(obj.get('MDDF', b'')), 36):
                    fid, uid, x, z, y, rx, ry, rz, scale, flags = struct.unpack_from('<II6fHH', obj['MDDF'], pos)
                    require(flags & 0x40, 'MDDF name-index placement needs listfile resolution')
                    xy, xyz, unknown = self.model_radius(fid)
                    radius = (xyz if abs(rx) > .01 or abs(rz) > .01 else xy) * scale / 1024
                    if radius or unknown:
                        obstacles.append(dict(type='M2', fdid=fid, uid=uid,
                                              center=[ORIGIN - y, ORIGIN - x], radius=radius + MARGIN,
                                              unknown=unknown))
                # MAI2 in this build references supplemental map textures. Check the
                # actual signatures rather than assuming it contains no new terrain.
                if 'MAI2' in wdt:
                    extra = struct.unpack_from('<8I', wdt['MAI2'], (ty * 64 + tx) * 32)
                    for fid in extra:
                        if fid:
                            require(self.casc.file(fid, 'WDT-MAI2-supplement')[:4] == b'BLP2',
                                    'unhandled MAI2 supplement')
                self.tiles[key] = terrain
                self.obstacles[key] = obstacles
                for ob in obstacles:
                    ident = (cont, ob['type'], ob['fdid'], ob['uid'])
                    if ob.get('unknown'):
                        self.unknown_object_tiles.add(key)
                    if ident in self.registered_objects:
                        continue
                    self.registered_objects.add(ident)
                    if 'bounds' in ob:
                        x0,y0,x1,y1 = ob['bounds']
                    else:
                        x,y = ob['center'];r = ob['radius']
                        x0,y0,x1,y1 = x-r,y-r,x+r,y+r
                    require((x1-x0)*(y1-y0) < 100000000, 'implausible object bounds')
                    for bx in range(math.floor(x0/CHUNK),math.floor(x1/CHUNK)+1):
                        for by in range(math.floor(y0/CHUNK),math.floor(y1/CHUNK)+1):
                            self.obstacle_bins.setdefault((cont,bx,by),[]).append(ob)
            except (EvidenceUnavailable, KeyError, struct.error) as exc:
                self.errors[str(key)] = str(exc)
                self.tiles[key] = None
                self.obstacles[key] = []
        return self.tiles[key]

    @lru_cache(maxsize=50000)
    def sample(self, cont, wx, wy):
        tx = math.floor(32 - wy / TILE)
        ty = math.floor(32 - wx / TILE)
        tile = self.tile(cont, tx, ty)
        if tile is None:
            return dict(missing=self.errors.get(str((cont, tx, ty)), 'missing tile'))
        s = tile.sample(wx, wy)
        s['objects'] = []
        # Placements in neighboring ADTs may project over this tile. Load a ring
        # and test all declared bounds, including copies stored at boundaries.
        ringkey=(cont,tx,ty)
        if ringkey not in self.loaded_rings:
            ring_unknown=False
            for ox,oy in ((ox,oy) for ox in range(tx-1,tx+2) for oy in range(ty-1,ty+2)):
                if not (0 <= ox < 64 and 0 <= oy < 64):
                    continue
                neighbor = self.tile(cont, ox, oy)
                # An absent neighboring terrain tile has no placements if MAID
                # says zero. Other extraction failures keep object coverage unknown.
                if neighbor is None:
                    f = struct.unpack_from('<8I', self.wdt(cont)['MAID'], (oy*64+ox)*32)
                    if f[0] or f[1]:
                        ring_unknown = True
                    continue
                if (cont,ox,oy) in self.unknown_object_tiles:
                    ring_unknown = True
            self.loaded_rings[ringkey]=ring_unknown
        s['unknown'] = s['unknown'] or self.loaded_rings[ringkey]
        for ob in self.obstacle_bins.get((cont,math.floor(wx/CHUNK),math.floor(wy/CHUNK)),[]):
            if 'bounds' in ob:
                x0, y0, x1, y1 = ob['bounds']
                inside = x0 <= wx <= x1 and y0 <= wy <= y1
            else:
                x, y = ob['center']
                inside = (wx-x)**2 + (wy-y)**2 <= ob['radius']**2
            if inside and len(s['objects']) < 5:
                s['objects'].append(dict(type=ob['type'], fdid=ob['fdid'], uid=ob['uid']))
        return s


def segment_points(a, b, spacing=2):
    """Dense profile plus midpoint of every height triangle cut by the chord.

    Four triangles meet at each unit-square center. Their edges are vertical,
    horizontal and the two diagonals. Add crossings with the global unit grid
    and sample each open interval; 2-yard sampling handles rounded MCNK origins.
    """
    ax, ay = a
    dx, dy = b[0] - ax, b[1] - ay
    distance = math.hypot(dx, dy)
    ts = {0.0, 1.0}
    for start, delta in [(ax, dx), (ay, dy), (ax-ay, dx-dy), (ax+ay, dx+dy)]:
        if abs(delta) > 1e-10:
            end = start + delta
            for k in range(math.floor(min(start,end)/UNIT), math.ceil(max(start,end)/UNIT)+1):
                t = (k*UNIT-start)/delta
                if 0 < t < 1:
                    ts.add(t)
    cuts = sorted(ts)
    ts.update((l+r)/2 for l,r in zip(cuts,cuts[1:]))
    n = max(1, math.ceil(distance/spacing))
    ts.update(i/n for i in range(n+1))
    return [(t, ax+t*dx, ay+t*dy) for t in sorted(ts)]


def classify(world, leg):
    a,b = leg['a'],leg['b']
    if a['cont'] != b['cont']:
        return dict(status='UNCERTAIN', reasons=['cross-instance endpoints'], samples=0)
    points = segment_points((a['wx'],a['wy']),(b['wx'],b['wy']))
    bad=[]; issues=Counter(); max_slope=0; min_z=math.inf; max_z=-math.inf; sources=set()
    for t,wx,wy in points:
        s=world.sample(a['cont'],wx,wy)
        if 'missing' in s:
            issues['missing-client-content']+=1
            continue
        sources.add(s['terrain_fdid']);max_slope=max(max_slope,s['slope'])
        min_z=min(min_z,s['z']);max_z=max(max_z,s['z'])
        if s['unknown']:issues['unsupported-or-missing-object-coverage']+=1
        if s['objects']:issues['placed-object-collision-needs-mesh']+=1
        if s['hole']:issues['terrain-hole-needs-interior-mesh']+=1
        if 45 < s['slope'] <= 52:issues['near-walkable-slope-threshold']+=1
        water=s['liquids']
        if any(w['max_depth']>.5 for w in water):issues['liquid-present']+=1
        reason=None
        if not s['unknown'] and not s['objects'] and not s['hole']:
            if s['slope']>52:reason='terrain-slope-over-52deg'
            elif any(w['min_depth']>2 for w in water):reason='liquid-depth-at-least-2yd'
        if reason:
            bad.append(dict(t=round(t,7),wx=round(wx,3),wy=round(wy,3),z=round(s['z'],3),
                            slope=round(s['slope'],3),reason=reason,terrain_fdid=s['terrain_fdid'],
                            chunk=s['chunk'],cell=s['cell'],triangle=s['triangle'],liquids=water))
    # Static heightfields can refute a straight walk. A clean surface profile
    # cannot prove object, dynamic-gameobject, faction, bridge or floor access.
    status='BLOCKED' if bad else 'UNCERTAIN'
    if not issues and not bad:issues['surface-clear-awaits-collision-or-continuous-ground-trace']=1
    return dict(status=status,samples=len(points),max_slope_deg=round(max_slope,3),
                height_range=None if min_z==math.inf else [round(min_z,3),round(max_z,3)],
                reasons=sorted(issues),issue_samples=dict(sorted(issues.items())),
                blocked_sample_count=len(bad),witnesses=bad[:3],
                worst_witness=max(bad,key=lambda s:s['slope']) if bad else None,
                terrain_fdids=sorted(sources))


class SavedLiteralParser:
    """Data-only SavedVariables parser: never executes supplied Lua."""
    token = re.compile(r'\s+|--[^\n]*|"(?:\\.|[^"\\])*"|\[(?:[^\]])*\]|[{}=,;]|'
                       r'-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|[A-Za-z_]\w*', re.S)

    def __init__(self,text):
        self.tokens=[];pos=0
        for m in self.token.finditer(text):
            require(not text[pos:m.start()].strip(),'unsupported SavedVariables syntax')
            t=m[0];pos=m.end()
            if not t.isspace() and not t.startswith('--'):self.tokens.append(t)
        require(not text[pos:].strip(),'unsupported SavedVariables tail')
        self.i=0

    @staticmethod
    def scalar(t):
        if t.startswith('"'):
            # Lua decimal escapes, unlike JSON octal escapes; common SV strings
            # use the JSON-compatible subset. Decode decimal first.
            t=re.sub(r'\\(\d{1,3})',lambda m: chr(int(m[1])),t)
            return json.loads(t)
        if t in ('true','false','nil'):return {'true':True,'false':False,'nil':None}[t]
        try:return float(t) if any(c in t for c in '.eE') else int(t)
        except ValueError:raise EvidenceUnavailable('nonliteral Lua value') from None

    def take(self):
        t=self.tokens[self.i];self.i+=1;return t

    def value(self):
        t=self.take()
        if t!='{':return self.scalar(t)
        result={};implicit=1
        while self.tokens[self.i]!='}':
            t=self.tokens[self.i]
            if t.startswith('['):
                key=self.scalar(self.take()[1:-1]);require(self.take()=='=','expected =');v=self.value()
            elif self.i+1<len(self.tokens) and self.tokens[self.i+1]=='=':
                key=self.take();self.take();v=self.value()
            else:key=implicit;implicit+=1;v=self.value()
            result[key]=v
            if self.tokens[self.i] in (',',';'):self.take()
        self.take();return result

    def parse(self):
        result={}
        while self.i<len(self.tokens):
            key=self.take();require(self.take()=='=','expected top-level assignment');result[key]=self.value()
        return result


def trail_evidence(path, legs):
    if not path:return dict(available=False),{}
    raw=Path(path).read_bytes()
    parsed=SavedLiteralParser(raw.decode()).parse()
    db=parsed.get('WaypointTrackerDB',{});trails=db.get('trails',{})
    own=trails.get('own',{});shared=trails.get('shared',{});pending=trails.get('pending',{})
    def size(grids):return sum(len(g) for g in grids.values() if isinstance(g,dict))
    def unkey(k):return k//4096-2048,k%4096-2048
    def key(x,y):return (x+2048)*4096+y+2048
    results={};edges=0;components=[]
    for cont,grid in own.items():
        unseen=set(grid);sizes=[]
        while unseen:
            start=unseen.pop();q=[start];n=0
            while q:
                k=q.pop();n+=1;x,y=unkey(k)
                for i,(dx,dy) in enumerate(DIRS):
                    nk=key(x+dx,y+dy)
                    if grid[k]&(1<<i) and grid.get(nk,0)&(1<<((i+4)%8)):
                        edges+=1
                        if nk in unseen:unseen.remove(nk);q.append(nk)
            sizes.append(n)
        components.append(dict(continent=cont,cells=len(grid),components=sorted(sizes,reverse=True)))
    for leg in legs:
        a,b=leg['a'],leg['b'];grid=own.get(a['cont'],{})
        if not grid:continue
        covered=0;total=0
        for _,wx,wy in segment_points((a['wx'],a['wy']),(b['wx'],b['wy']),spacing=20):
            total+=1
            if key(math.floor(wx/20),math.floor(wy/20)) in grid:covered+=1
        # Cell occupancy (and plans in travelLog) proves neither the full chord
        # nor continuity; keep this separate from status, even with 100% occupancy.
        results[leg['id']]=dict(own_cell_sample_fraction=round(covered/max(1,total),5),
                                occupied_samples=covered,total_samples=total,
                                confirms_exact_straight_leg=False)
    log=db.get('travelLog',{})
    times=[row.get('when') for row in log.values() if isinstance(row,dict) and isinstance(row.get('when'),(int,float))]
    positions=[]
    for row in log.values():
        if isinstance(row,dict) and isinstance(row.get('here'),str):
            m=re.match(r'(\d+) ([\d.]+) ([\d.]+) \| (\d+) (-?[\d.]+) (-?[\d.]+)',row['here'])
            if m:positions.append(dict(map=int(m[1]),x=float(m[2]),y=float(m[3]),cont=int(m[4]),wx=float(m[5]),wy=float(m[6])))
    return dict(available=True,sha256=hashlib.sha256(raw).hexdigest(),own_cells=size(own),shared_cells=size(shared),
                pending_cells=size(pending),reciprocal_directed_edges=edges,components=components,
                crossings=len(trails.get('crossings',{})),travel_log_entries=len(log),
                travel_log_time_range=[min(times),max(times)] if times else None,
                travel_log_position_maps=dict(Counter(str(p['map']) for p in positions)),
                exact_legs_confirmed=0,
                limitation='20yd cell links have no per-edge mode/height/timestamp; travelLog records plans, not continuous ground movement'),results


def candidate_path(world, a, b, limit=60000):
    """Bounded terrain A*: returns a proposal, never a collision certificate.

    12.5yd nodes, <=2yd / triangle-intersection edge checks, 400yd envelope,
    <=45deg faces and <=0.5yd liquid depth. Object bounds are retained as
    uncertainty in the proposal; skipping entire bridge/building AABBs would
    frequently prevent reaching a real service endpoint.
    """
    if a['cont']!=b['cont']:return dict(status='UNCERTAIN',reason='cross-instance')
    step=12.5;cont=a['cont'];start=(round(a['wx']/step),round(a['wy']/step));goal=(round(b['wx']/step),round(b['wy']/step))
    lower=(math.floor(min(a['wx'],b['wx'])/step)-32,math.floor(min(a['wy'],b['wy'])/step)-32)
    upper=(math.ceil(max(a['wx'],b['wx'])/step)+32,math.ceil(max(a['wy'],b['wy'])/step)+32)
    cache={}
    def valid(p):
        if p not in cache:
            s=world.sample(cont,p[0],p[1])
            cache[p]=('missing' not in s and not s['hole'] and not s['unknown'] and s['slope']<=45
                      and all(w['max_depth']<=.5 for w in s['liquids']))
        return cache[p]
    def edge(p,q):return all(valid((x,y)) for _,x,y in segment_points(p,q))
    sp=(start[0]*step,start[1]*step);gp=(goal[0]*step,goal[1]*step)
    if not edge((a['wx'],a['wy']),sp) or not edge(gp,(b['wx'],b['wy'])):
        return dict(status='UNCERTAIN',reason='endpoint needs object/floor/interior collision path')
    queue=[(math.dist(start,goal)*step,0,start)];cost={start:0};prev={};expanded=0
    while queue and expanded<limit:
        _,g,p=heapq.heappop(queue)
        if g!=cost[p]:continue
        if p==goal:
            path=[p]
            while p!=start:p=prev[p];path.append(p)
            path=[(a['wx'],a['wy'])]+[(x*step,y*step) for x,y in reversed(path)]+[(b['wx'],b['wy'])]
            # Greedy shortcuts must pass the same dense edge validator.
            simple=[path[0]];i=0
            while i<len(path)-1:
                j=min(len(path)-1,i+32)
                while j>i+1 and not edge(path[i],path[j]):j-=1
                simple.append(path[j]);i=j
            length=sum(math.dist(p,q) for p,q in zip(simple,simple[1:]))
            object_points=0;fdids=set()
            for p,q in zip(simple,simple[1:]):
                for _,x,y in segment_points(p,q):
                    s=world.sample(cont,x,y);fdids.add(s['terrain_fdid'])
                    if s['objects']:object_points+=1
            return dict(status='UNCERTAIN',reason='terrain-following candidate; full object/access validation pending',
                        expanded=expanded,length_yards=round(length,2),
                        straight_ratio=round(length/max(.01,math.hypot(a['wx']-b['wx'],a['wy']-b['wy'])),4),
                        object_overlap_samples=object_points,terrain_fdids=sorted(fdids),
                        waypoints_world=[[round(x,3),round(y,3)] for x,y in simple])
        expanded+=1
        for dx,dy in DIRS:
            q=(p[0]+dx,p[1]+dy)
            if not (lower[0]<=q[0]<=upper[0] and lower[1]<=q[1]<=upper[1]):continue
            ng=g+math.hypot(dx,dy)*step
            if ng>=cost.get(q,math.inf):continue
            if not edge((p[0]*step,p[1]*step),(q[0]*step,q[1]*step)):continue
            cost[q]=ng;prev[q]=p;heapq.heappush(queue,(ng+math.dist(q,goal)*step,ng,q))
    return dict(status='UNCERTAIN',reason='bounded terrain search exhausted; not proof of no route',expanded=expanded)


def write_summary(output, data):
    """Compact new-file-only table; JSON remains the complete evidence record."""
    output=Path(output)
    require(not output.exists(),'refusing to overwrite an existing summary')
    columns=['id','kind','status','map','max_slope_deg','blocked_samples','witness_map_x',
             'witness_map_y','witness_reason','terrain_fdid','replacement_points','replacement_reason']
    with (ROOT/'tools/fixtures/travel/UiMapAssignment.csv').open() as stream:
        maps={int(r['UiMapID']):r for r in csv.DictReader(stream) if r['UiMin_0']=='0' and r['UiMax_0']=='1'}
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open('x') as stream:
        writer=csv.DictWriter(stream,fieldnames=columns,delimiter='\t',lineterminator='\n')
        writer.writeheader()
        for r in data['records']:
            w=r.get('worst_witness') or {};m=maps[r['a']['map']];q=r.get('replacement',{})
            top,left=float(m['Region_3']),float(m['Region_4'])
            height,width=top-float(m['Region_0']),left-float(m['Region_1'])
            writer.writerow(dict(id=r['id'],kind=r['kind'],status=r['status'],map=r['a']['map'],
                max_slope_deg=r.get('max_slope_deg',''),blocked_samples=r.get('blocked_sample_count',0),
                witness_map_x=round((left-w['wy'])/width*100,4) if w else '',
                witness_map_y=round((top-w['wx'])/height*100,4) if w else '',
                witness_reason=w.get('reason',''),terrain_fdid=w.get('terrain_fdid',''),
                replacement_points=len(q.get('waypoints_world',[])),replacement_reason=q.get('reason','')))


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--install',default='/Applications/World of Warcraft')
    ap.add_argument('--saved',help='Account SavedVariables file; by default use the newest local account snapshot; empty string disables')
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--summary',type=Path,help='Optional new TSV review artifact')
    ap.add_argument('--replacements',action='store_true')
    ap.add_argument('--search-limit',type=int,default=60000)
    ap.add_argument('--force-new-artifact',action='store_true',help='Replace only this tool\'s prior schema-tagged artifact')
    args=ap.parse_args()
    if args.saved is None:
        snapshots=list((Path(args.install)/'_classic_beta_/WTF/Account').glob('*/SavedVariables/WaypointTracker.lua'))
        args.saved=str(max(snapshots,key=lambda p:p.stat().st_mtime)) if snapshots else ''
    if args.output.exists():
        require(args.force_new_artifact and json.loads(args.output.read_text()).get('schema')=='wt-terrain-evidence-v1',
                'refusing to overwrite an existing file')
    require('WTF' not in args.output.parts and not args.output.resolve().is_relative_to(Path(args.install).resolve()),
            'output must be outside the client')
    if args.summary:
        require(not args.summary.exists() and 'WTF' not in args.summary.parts
                and not args.summary.resolve().is_relative_to(Path(args.install).resolve()),
                'summary must be a new file outside the client')
    start=time.monotonic()
    inputs=['WaypointTracker/TravelData.lua','tools/travel_extra.tsv','docs/data-walking-review.tsv',
            'tools/fixtures/travel/UiMapAssignment.csv','tools/fixtures/travel/Map.csv']
    hashes={p:sha(ROOT/p) for p in inputs}
    legs,barriers,maps=load_inputs()
    casc=LocalCASC(args.install)
    require(casc.build['Version!STRING:0']=='1.60.1.70338',
            'map fixtures require build 1.60.1.70338; refresh/pin fixtures before another build')
    world=World(casc)
    print('Loaded local CASC:',casc.build['Version!STRING:0'],casc.root_entries,'root entries',flush=True)
    records=[]
    for i,leg in enumerate(legs):
        result=classify(world,leg)
        records.append(dict(id=leg['id'],kind=leg['kind'],a=leg['a'],b=leg['b'],**result))
        if (i+1)%5==0:print('Classified',i+1,'/',len(legs),dict(Counter(r['status'] for r in records)),flush=True)
    replacements={}
    if args.replacements:
        unique={}
        for r in records:
            if r['status']!='BLOCKED' or r['kind'] not in {'review-leg','road-approach'}:continue
            key=tuple(sorted([r['a']['id'],r['b']['id']]))
            if key not in unique:
                print('Terrain path proposal:',r['id'],flush=True)
                unique[key]=candidate_path(world,r['a'],r['b'],args.search_limit)
                unique[key]['from']=r['a']['id'];unique[key]['to']=r['b']['id']
            replacements[r['id']]=dict(unique[key])
            if unique[key]['from']!=r['a']['id'] and 'waypoints_world' in replacements[r['id']]:
                replacements[r['id']]['waypoints_world']=list(reversed(replacements[r['id']]['waypoints_world']))
                replacements[r['id']]['from']=r['a']['id'];replacements[r['id']]['to']=r['b']['id']
    trail_summary,trail_rows=trail_evidence(args.saved if args.saved and Path(args.saved).exists() else None,legs)
    for r in records:
        if r['id'] in trail_rows:r['passive_evidence']=trail_rows[r['id']]
        if r['id'] in replacements:
            proposal=replacements[r['id']]
            if 'waypoints_world' in proposal:
                mid=r['a']['map'];m=maps[mid]
                top,left=float(m['Region_3']),float(m['Region_4'])
                height,width=top-float(m['Region_0']),left-float(m['Region_1'])
                proposal['waypoints_map']=[[mid,round((left-y)/width*100,4),round((top-x)/height*100,4)]
                                           for x,y in proposal['waypoints_world']]
            r['replacement']=proposal
        elif r['status']=='BLOCKED':
            r['replacement']=dict(status='UNCERTAIN',reason='crossing diagnostic or no replacement requested')
    for barrier in barriers:
        probes=[r for r in records if r['id'].startswith(barrier['id']+'-crossing-')]
        barrier['probe_counts']=dict(Counter(r['status'] for r in probes))
        barrier['status']='UNCERTAIN'
        barrier['reason']='discrete crossing probes cannot establish a continuous separating wall or exact extents'
    require(all(sha(ROOT/p)==h for p,h in hashes.items()),'concurrent input change; rerun against a stable snapshot')
    output=dict(schema='wt-terrain-evidence-v1',build=dict(product=casc.build['Product!STRING:0'],
                version=casc.build['Version!STRING:0'],build_key=casc.build_key,root_ckey=casc.config['root'][0]),
                parameters=dict(sample_yards=2,walkable_slope_deg=50,blocked_slope_deg=52,
                                candidate_max_slope_deg=45,deep_liquid_lower_bound_yards=2,
                                object_margin_yards=MARGIN,astar_grid_yards=12.5,
                                astar_padding_yards=400,astar_expansion_limit=args.search_limit),
                semantics=dict(PASSABLE='Reserved for collision-complete validated path or continuous ground traversal; never inferred from a clean heightfield',
                               BLOCKED='Straight ground walk refuted by a steep terrain face or deep liquid outside placed-object bounds; not unreachable destination',
                               UNCERTAIN='Missing evidence, possible alternate object surface, near-threshold slope, or unconfirmed clear surface'),
                input_sha256=hashes,
                tool_sha256={str(p.relative_to(ROOT)):sha(p) for p in
                             [ROOT/'tools/verify_legs_casc.py',Path(__file__)]},
                counts_by_kind={k:dict(Counter(r['status'] for r in records if r['kind']==k))
                                                  for k in sorted({r['kind'] for r in records})},
                records=records,barriers=barriers,passive_summary=trail_summary,
                client_content_manifest=casc.manifest,extraction_errors=world.errors,
                runtime_seconds=round(time.monotonic()-start,2))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,indent=2,sort_keys=True)+'\n')
    if args.summary:write_summary(args.summary,output)
    print(json.dumps(output['counts_by_kind'],sort_keys=True),flush=True)
    print('Wrote',args.output,'in',output['runtime_seconds'],'seconds;',len(casc.manifest),'client files checked')


if __name__=='__main__':main()
