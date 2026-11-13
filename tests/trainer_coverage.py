"""Independent offline resolver for DB.MapForArea, FromClassicMap and shipped DB.Points.
Uses real pinned client rectangles, not wowmock maps. No addon execution.
"""
from pathlib import Path
import csv,re,json,collections,math
ROOT=Path(__file__).resolve().parents[1]
def client_rows(table):
 with (ROOT / ('tools/fixtures/client/' + table + '-1.60.1.70862-enUS.csv')).open() as stream:
  return list(csv.DictReader(stream))
class Resolver:
 def __init__(self):
  self.maps={int(r['ID']):r for r in client_rows('UiMap')};self.geo={}
  for r in client_rows('UiMapAssignment'):
   m=int(r['UiMapID'])
   if [r[k] for k in ['UiMin_0','UiMin_1','UiMax_0','UiMax_1']]!=['0','0','1','1'] or m in self.geo:continue
   top,left=float(r['Region_3']),float(r['Region_4']);w=left-float(r['Region_1']);h=top-float(r['Region_0'])
   if w and h:self.geo[m]=dict(cont=int(r['MapID']),top=top,left=left,w=w,h=h)
  self.names=self.block(ROOT/'WaypointTracker_Data/Names_enUS.lua','zones')
  self.client_areas=json.loads((ROOT/'tools/fixtures/trainers/client-areas-1.60.1.70862.json').read_text())['records']
  self.area={}
  for i,f in self.names.items():
   names=list(dict.fromkeys([self.client_areas.get(str(i),{}).get('AreaName_lang'),f[1]]))
   opts=[]
   for name in names:
    if name:
     opts=[m for m,n in self.maps.items() if m in self.geo and n['Name_lang'].lower()==name.lower()]
     if opts:break
   # Same name preference as MapForArea: zone first, then the continent-parent map.
   opts.sort(key=lambda m:(self.maps[m]['Type']!='3',self.maps.get(int(self.maps[m]['ParentUiMapID']),{}).get('Type')!='2',m))
   if opts:self.area[i]=opts[0]
  self.units=self.block(ROOT/'WaypointTracker_Data/Data.lua','units');self.extra=collections.defaultdict(list)
  for source in ['Curated','Forever']:
   cells = collections.defaultdict(set)
   for line in (ROOT/'WaypointTracker_Data'/ (source+'.lua')).read_text().splitlines():
    f=line.split('\t')
    if f[0]=='N' and len(f)>6:
     for m,x,y in self.parse(f[6],1000):
      # Learn.Import/AddSpot keeps one point per 1% square per source.
      cell = (m, math.floor(x * 100), math.floor(y * 100))
      if cell not in cells[int(f[1])]:
       cells[int(f[1])].add(cell)
       self.extra[int(f[1])].append((m,x,y,source=='Curated'))
  self.bounds={1412:(1,-3697.9165,-3089.5833,-272.9167,2047.9166),1423:(0,1218.75,-6056.25,3799.9998,-2185.4165),1433:(0,-10022.916,-3741.6665,-8575,-1570.8332),1453:(0,-9175.205,36.7006,-8278.8506,1380.9714)}
 @staticmethod
 def block(p,key):
  s=p.read_text().split(key+' = [==[\n',1)[1].split(']==]',1)[0]
  return {int(f[0]):f for f in (line.split('\t') for line in s.splitlines())}
 @staticmethod
 def parse(s,scale=1):
  out=[]
  for token in s.split(';') if s else []:
   m,nums=token.split(':');nums=list(map(float,nums.split(',')))
   out.extend((int(m),nums[k]/scale,nums[k+1]/scale) for k in range(0,len(nums)-1,2))
  return out
 def world(self,p):
  m,x,y=p;g=self.geo[m];return g['cont'],g['top']-y*g['h'],g['left']-x*g['w']
 def distance(self,a,b):
  if a[0] not in self.geo or b[0] not in self.geo:return None
  ac,ax,ay=self.world(a);bc,bx,by=self.world(b)
  return math.hypot(ax-bx,ay-by) if ac==bc else float('inf')
 def classic(self,m,x,y):
  if m in self.bounds and m in self.geo:
   cont,x0,y0,x1,y1=self.bounds[m];wx=x1-y*(x1-x0);wy=y1-x*(y1-y0);g=self.geo[m]
   return m,(g['left']-wy)/g['w'],(g['top']-wx)/g['h']
  return m,x,y
 def points(self,i):
  extra=self.extra[i];curated={p[0] for p in extra if p[3]};seen={p[0] for p in extra if not p[3]};by=collections.defaultdict(list)
  row=self.units.get(i)
  for area,x,y in self.parse(row[4] if row else '',1000):
   m=self.area.get(area)
   if m:by[m].append(self.classic(m,x,y))
  out=[p[:3] for p in extra]
  for m,points in by.items():
   if m not in curated and not (m in seen and len(points)<=2):out+=points
  return out

CAPITALS = {'Stormwind': (1453, 'A'), 'Ironforge': (1455, 'A'),
            'Darnassus': (1457, 'A'), 'Orgrimmar': (1454, 'H'),
            'Undercity': (1458, 'H'), 'Thunder Bluff': (1456, 'H')}

def roster_points(resolver, row):
    """Same shipped precedence as TrainerEntries, without personal SavedVariables."""
    pinned = resolver.parse(row.get('positions', ''))
    raw = resolver.points(int(row['npc_id']))
    return pinned if row.get('position_mode') in ('observed', 'player') else (raw or pinned)

def capital_matrix(rows, classes, professions):
    resolver = Resolver()
    matrix = {}
    for capital, (map_id, faction) in CAPITALS.items():
        counts = {(kind, sub): set() for kind, subs in [('class', classes), ('profession', professions)] for sub in subs}
        geometry = resolver.geo[map_id]
        for row in rows:
            key = row['kind'], row['subkind']
            if key not in counts or faction not in row['faction']:
                continue
            for point in roster_points(resolver, row):
                if point[0] not in resolver.geo:
                    continue
                continent, wx, wy = resolver.world(point)
                x = (geometry['left'] - wy) / geometry['w']
                y = (geometry['top'] - wx) / geometry['h']
                # Map aliases can put a city trainer on its surrounding zone map.
                if continent == geometry['cont'] and 0 <= x <= 1 and 0 <= y <= 1:
                    counts[key].add(row['npc_id'])
                    break
        matrix[capital] = counts
    return matrix

def fact_capital_counts():
    """Independent source censuses; faction is not inferred from a city."""
    import build_trainers as build
    resolver = Resolver()
    result = {}
    for source, data in build.fact_sources().items():
        counts = {capital: collections.defaultdict(set) for capital in CAPITALS}
        for ident, record in data['records'].items():
            roles = build.fact_roles(record)
            worlds = []
            if source == 'questie':
                for area, pairs in (record.get('spawns') or {}).items():
                    m = resolver.area.get(int(area))
                    if m not in resolver.geo:
                        continue
                    for pair in pairs.values():
                        x, y = pair['1'] / 100, pair['2'] / 100
                        if 0 <= x <= 1 and 0 <= y <= 1:
                            worlds.append(resolver.world(resolver.classic(m, x, y)))
            else:
                for point in record.get('spawns', []):
                    if point.get('patch_min', 0) <= 10 <= point.get('patch_max', 10):
                        worlds.append((point['map'], point['position_x'], point['position_y']))
            for capital, (map_id, faction) in CAPITALS.items():
                g = resolver.geo[map_id]
                if any(cont == g['cont'] and 0 <= (g['left'] - wy) / g['w'] <= 1 and 0 <= (g['top'] - wx) / g['h'] <= 1 for cont, wx, wy in worlds):
                    for role in roles:
                        counts[capital][role].add(ident)
        result[source] = counts
    return result


def coverage_gaps(rows, classes, professions, audit=None):
    """Each exception must match a pinned, reviewed three-source zero census."""
    import build_trainers as build
    import hashlib
    audit = (ROOT / 'docs/data-audit.md').read_text() if audit is None else audit
    matrix = capital_matrix(rows, classes, professions)
    reviewed = {}
    pattern = r'^TRAINER_ABSENCE\|([^|]+)\|([AH])\|(class|profession)\|([a-z]+)\|(https://[^|\s]+)\|([0-9a-f]{64})\|(.{40,})$'
    matches = list(re.finditer(pattern, audit, re.M))
    if matches:
        path = ROOT / 'tools/fixtures/trainers/capital-absences.json'
        raw = path.read_bytes()
        proof = json.loads(raw)
        census = fact_capital_counts()
        for match in matches:
            capital, faction, kind, sub, url, digest, reason = match.groups()
            key = capital, kind, sub
            record = next((v for v in proof['reviews'] if (v['capital'], v['kind'], v['subkind']) == key), None)
            if not record or faction != CAPITALS.get(capital, (None, None))[1] or digest != hashlib.sha256(raw).hexdigest() or url != build.fact_sources()['vmangos']['url'] or reason != record['reason']:
                raise ValueError('absence review does not match pinned evidence: ' + repr(key))
            if any(census[source][capital].get((kind, sub)) for source in ('vmangos', 'cmangos', 'questie')):
                raise ValueError('absence contradicted by source census: ' + repr(key))
            if record['source_counts'] != {source: 0 for source in ('vmangos', 'cmangos', 'questie')} or not record.get('att_city_review') or proof.get('att_commit') != build.ATT_PIN:
                raise ValueError('absence lacks current independent source reviews: ' + repr(key))
            # Unknown access cannot be turned into a claim of physical absence.
            unknown = [dict(row, faction=faction) for row in rows if not row['faction']]
            if capital_matrix(unknown, classes, professions)[capital][kind, sub]:
                raise ValueError('absence contradicted by unknown-access Forever identity: ' + repr(key))
            reviewed[key] = record
    gaps = [(capital, CAPITALS[capital][1], kind, sub)
            for capital, counts in matrix.items() for (kind, sub), ids in counts.items()
            if not ids and (capital, kind, sub) not in reviewed]
    return matrix, gaps


def print_matrix(matrix, classes, professions):
    for kind, subs in [('class', classes), ('profession', professions)]:
        print('\nTrainer capital coverage: ' + kind)
        print('Capital / faction | ' + ' | '.join(subs))
        for capital, counts in matrix.items():
            print(capital + ' / ' + CAPITALS[capital][1] + ' | ' + ' | '.join(str(len(counts[kind, sub])) for sub in subs))


def town_matrix(rows):
    """Index towns using the same pinned AreaPOI icon family as Client.lua.

    Points attach to the nearest town marker within 600 world yards. This is
    an inventory of nearby trainers, not a certification of town boundaries.
    The active-source identity gate separately covers trainers outside towns.
    """
    resolver = Resolver()
    towns = {int(v['ID']): v for v in client_rows('AreaPOI')
             if v['Name_lang'] and v['Icon'] in ('4', '5', '6') and v['ContinentID'] in ('0', '1')}
    counts = collections.defaultdict(lambda: collections.defaultdict(set))
    for row in rows:
        if row['kind'] not in ('class', 'profession', 'weapon', 'riding', 'pet'):
            continue
        for point in roster_points(resolver, row):
            if point[0] not in resolver.geo:
                continue
            cont, wx, wy = resolver.world(point)
            near = [(math.hypot(wx - float(v['Pos_0']), wy - float(v['Pos_1'])), ident)
                    for ident, v in towns.items() if cont == int(v['ContinentID'])]
            if not near:
                continue
            distance, ident = min(near)
            if distance > 600:
                continue
            for faction in ('A', 'H'):
                if faction in row['faction']:
                    counts[towns[ident]['Name_lang'], faction][row['kind'], row['subkind']].add(row['npc_id'])
    return counts


def print_towns(counts):
    print('\nTrainer town coverage (pinned client markers, nearest within 600 yards)')
    print('Town / faction | class NPCs | profession NPCs | weapon | riding | pet | classes | professions')
    for (town, faction), roles in sorted(counts.items()):
        total = lambda kind: len(set().union(*(ids for (k, sub), ids in roles.items() if k == kind)))
        subs = lambda kind: ','.join(sorted(sub for k, sub in roles if k == kind and roles[k, sub])) or '-'
        print(f'{town} / {faction} | {total("class")} | {total("profession")} | {total("weapon")} | {total("riding")} | {total("pet")} | {subs("class")} | {subs("profession")}')
