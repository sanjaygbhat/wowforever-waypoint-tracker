#!/usr/bin/env python3
"""Audit real runtime service coverage against pinned client map tables, offline."""
import argparse
import csv
import json
import os
import shutil
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path
from service_maps import ROOT, BUILD, tables, lua_prelude, read_csv

TOWNS={
 'Alliance':['Goldshire','Kharanos','Thelsamar','Lakeshire','Sentinel Hill','Darkshire','Menethil Harbor','Southshore','Auberdine','Astranaar'],
 'Horde':['Brill','The Sepulcher','Razor Hill','Bloodhoof Village','The Crossroads','Camp Taurajo','Sun Rock Retreat','Stonard','Tarren Mill','Freewind Post']}
CAPITALS={'Alliance':[1453,1455,1457],'Horde':[1454,1456,1458]}

def origins():
    maps,_=tables();out=[]
    pois=read_csv(ROOT/f'tools/fixtures/client/AreaPOI-{BUILD}-enUS.csv')
    for faction,mids in CAPITALS.items():
        for mid in mids:
            m=maps[mid];out.append(dict(faction=faction,name=m['name'],map=mid,cont=m['cont'],wx=m['top']-.5*m['h'],wy=m['left']-.5*m['w'],evidence='UiMapAssignment; map centre survey origin'))
        for name in TOWNS[faction]:
            matches=[r for r in pois if r['Name_lang']==name]
            if not matches:raise ValueError('missing literal town origin '+name)
            r=matches[0];out.append(dict(faction=faction,name=name,cont=int(r['ContinentID']),wx=float(r['Pos_0']),wy=float(r['Pos_1']),evidence='AreaPOI '+r['ID']))
    return out

def _probe(lua=None, baseline=None, initial_faction='Alliance'):
    lua=lua or os.environ.get('LUA51') or shutil.which('lua5.1')
    if not lua:raise ValueError('Lua 5.1 is required (LUA51)')
    places=origins()
    def literal(v):return json.dumps(v,ensure_ascii=False)
    code=lua_prelude()
    if baseline:
        overrides={str(ROOT/k):str(Path(baseline)/v) for k,v in [('WaypointTracker/Database.lua','Database.lua'),('WaypointTracker_Data/Forever.lua','Forever.lua'),('WaypointTracker_Data/Client.lua','Client.lua')]}
        # wowmock passes relative paths to loadfile.
        overrides.update({k.removeprefix(str(ROOT)+'/'):v for k,v in list(overrides.items())})
        code+='local originalLoadfile=loadfile\nlocal overrides={'+','.join('['+literal(k)+']='+literal(v) for k,v in overrides.items())+'}\nloadfile=function(path) return originalLoadfile(overrides[path] or path) end\n'
    code+='local auditBaseline='+('true' if baseline else 'false')+'\n'
    code+='local initialFaction='+literal(initial_faction)+'\n'
    code+='local origins={'+','.join('{'+','.join(k+'='+literal(v) for k,v in p.items())+'}' for p in places)+'}\n'+(ROOT/'tests/service_probe.lua').read_text()
    with tempfile.TemporaryDirectory(prefix='service-audit-') as tmp:
        f=Path(tmp)/'probe.lua';f.write_text(code)
        r=subprocess.run([lua,str(f)],cwd=ROOT,capture_output=True,text=True,timeout=45)
    if r.returncode:raise ValueError(r.stderr+'\n'+r.stdout[-2000:])
    entries=[];nearest=[];roster=[]
    for line in r.stdout.splitlines():
        f=line.split('\t')
        if f[0]=='ENTRY':
            pts=[]
            for raw in filter(None,f[7].split(';')):
                mid,xy=raw.split(':');x,y=map(float,xy.split(','));pts.append(dict(m=int(mid),x=x,y=y))
            entries.append(dict(faction=f[1],service=f[2],kind=f[3],id=int(f[4]),name=f[5],classic=f[6],points=pts,access=f[8],learned=f[9]))
        elif f[0]=='NEAREST':
            nearest.append(dict(faction=f[1],origin=f[2],service=f[3],name=f[4],map=int(f[5]) if f[5] else None,distance=float(f[6]) if f[6] else None,id=int(f[7]) if f[7] else None,x=float(f[8]) if f[8] else None,y=float(f[9]) if f[9] else None))
        elif f[0]=='ROSTER':
            spawns=[]
            for raw in filter(None,f[5].split(';')):
                a,x,y,mid,nx,ny=raw.split(',');spawns.append(dict(area=int(a),classic_x=float(x),classic_y=float(y),map=int(mid) if mid else None,x=float(nx) if nx else None,y=float(ny) if ny else None))
            roster.append(dict(service=f[1],id=int(f[2]),fac=f[3],name=f[4],spawns=spawns))
    return dict(build=BUILD,origins=places,entries=entries,nearest=nearest,roster=roster)

def probe(lua=None, baseline=None):
    # Legacy WTL1 service rows without explicit access use the viewer's faction
    # during merge. Switching a mock player's faction after Load is therefore
    # not equivalent to loading that character: use a fresh state for each.
    profiles=[_probe(lua,baseline,faction) for faction in ('Alliance','Horde')]
    result=dict(build=BUILD,origins=[],entries=[],nearest=[],roster=profiles[0]['roster'])
    for faction,data in zip(('Alliance','Horde'),profiles):
        for key in ('origins','entries','nearest'):
            result[key].extend(row for row in data[key] if row['faction']==faction)
    return result

def summarize(data):
    maps,_=tables();stats={};zones=defaultdict(lambda:defaultdict(int));gaps=[]
    full=json.loads((ROOT/'tools/fixtures/services/pfquest-roster.json').read_text())['roster']
    for row in data['roster']:
        row['name']=full[row['service']][str(row['id'])]['name']
    identities=defaultdict(set);positioned=defaultdict(set);locations=defaultdict(set)
    excluded=[]
    for r in data['entries']:
        # Match Find's enabled general faction filter as well as the service
        # roster's access. Old community merges can override an entry's side
        # while its original service-row access remains broader.
        if r['access'] and r['faction'][0] not in r['access']:
            excluded.append(dict(faction=r['faction'],service=r['service'],id=r['id'],name=r['name'],reason='entry faction excludes player after discovery merge'))
            continue
        key=r['service']+'/'+r['faction'];identity=(r['kind'],r['id'])
        identities[key].add(identity)
        if r['points']:positioned[key].add(identity)
        if not r['points']:gaps.append(dict(service=r['service'],faction=r['faction'],id=r['id'],name=r['name'],reason='no coordinates' if not r['classic'] else 'area not mapped or positions rejected by corrections'))
        for p in r['points']:locations[key].add(identity+(p['m'],p['x'],p['y']))
    zone_ids=defaultdict(set)
    for key,ids in identities.items():
        stats[key]=dict(identities=len(ids),positioned=len(positioned[key]),spawns=len(locations[key]))
        for kind,rid,mid,x,y in locations[key]:
            zone=str(mid)+' '+maps[mid]['name'];zones[key][zone]+=1;zone_ids[key+'/'+zone].add((kind,rid))
    data['zone_identities']={key:len(ids) for key,ids in zone_ids.items()}
    # The full pfQuest metadata roster includes rows the old generator omitted
    # because its source provided no coordinates. Keep those gaps explicit.
    raw_stats={};raw_gaps=[];replacements=[]
    for faction,letter in [('Alliance','A'),('Horde','H')]:
        for r in data['roster']:
            if letter not in r['fac']:continue
            key=r['service']+'/'+faction;s=raw_stats.setdefault(key,dict(identities=0,positioned=0,spawns=0,resolved_spawns=0))
            s['identities']+=1;s['spawns']+=len(r['spawns']);s['positioned']+=any(p['map'] for p in r['spawns'])
            s['resolved_spawns']+=sum(bool(p['map']) for p in r['spawns'])
            if not r['spawns']:raw_gaps.append(dict(service=r['service'],faction=faction,id=r['id'],name=r['name'],reason='pinned pfQuest roster has no spawn coordinates'))
            for p in r['spawns']:
                if not p['map']:raw_gaps.append(dict(service=r['service'],faction=faction,id=r['id'],name=r['name'],area=p['area'],reason='area not mapped by runtime resolver'))
                else:
                    kind='object' if r['id']<0 else 'npc'
                    pts=[v for k,i,mid,x,y in locations[key] if k==kind and i==abs(r['id']) and mid==p['map'] for v in [(x,y)]]
                    if pts and not any(abs(x-p['x'])<1e-9 and abs(y-p['y'])<1e-9 for x,y in pts):
                        replacements.append(dict(service=r['service'],faction=faction,id=r['id'],map=p['map'],x=p['x'],y=p['y'],reason='curated/community position replaces the Classic source position'))
    data.update(raw_summary=raw_stats,raw_unresolved=raw_gaps,replaced_classic_spawns=replacements)
    data.update(summary=stats,by_zone=dict(zones),unresolved=gaps,faction_excluded=excluded)
    return data

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--lua');ap.add_argument('--baseline',type=Path);a=ap.parse_args()
    data=summarize(probe(a.lua,a.baseline));a.output.write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
    for key,r in sorted(data['summary'].items()):print(key,r)
if __name__=='__main__':main()
