#!/usr/bin/env python3
"""Reduce pinned EG Link JSON and ATT Camelot text to service evidence.

No network or downloaded code execution. Usage: extract_services.py EG_ROOT
ATT_ROOT. The revisions are explicit and the complete source-file SHA-256 is
retained for each reduced record. build_services.py consumes the offline extract.
"""
import argparse
import hashlib
import json
import re
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EG_PIN = 'e0f8585914c134d9cb5d76756bd065b1e3e92ece'
ATT_PIN = '1c4d146b518a3c2cda6d2488a27be6e2638d5360'
INTERACTIONS = {'Merchant':'vendor', 'Binder':'innkeeper', 'TaxiNode':'flight',
                'Banker':'banker', 'CharacterBanker':'banker', 'Auctioneer':'auctioneer',
                'StableMaster':'stablemaster', 'SpiritHealer':'spirithealer', 'BattleMaster':'battlemaster'}

def title_services(name, title):
    out = set()
    if title == 'Innkeeper': out.add('innkeeper')
    if title == 'Banker': out.add('banker')
    if title in ('Auctioneer','Seafaring Auctioneer'): out.add('auctioneer')
    if title in ('Stable Master','Stablemaster'): out.add('stablemaster')
    if title.endswith('Battlemaster'): out.add('battlemaster')
    if title in ('Gryphon Master','Hippogryph Master','Wind Rider Master','Bat Handler','Flight Master',
                 'Darnassus Flight Master','Thunder Bluff Flight Master'): out.add('flight')
    if re.search(r'\b(Merchant|Vendor|Supplies|General Goods|Trade Goods)\b', title): out.add('vendor')
    if name == 'Spirit Healer': out.add('spirithealer')
    return out

def balanced(text, start):
    """Return a brace-balanced literal, ignoring quoted text and comments."""
    depth=0; quoted=None; escaped=False
    for i in range(start,len(text)):
        c=text[i]
        if quoted:
            if escaped: escaped=False
            elif c=='\\': escaped=True
            elif c==quoted: quoted=None
        elif c in '\"\'': quoted=c
        elif c=='{': depth+=1
        elif c=='}':
            depth-=1
            if depth==0: return text[start:i+1],i+1
    raise ValueError('unterminated table')

def extract(eg, att):
    paths=sorted(eg.glob('data/*/*/*.json'), key=lambda p:(tuple(map(int,p.parent.name.split('.'))),p.parent.parent.name=='wowf',p.name))
    chosen=set(); objects=set()
    for p in paths:
        if p.name not in ('creature_details.enUS.json','npcs.json','vendors.json','object_details.enUS.json'): continue
        j=json.loads(p.read_text())
        for i,r in j.get('creatures',{}).items():
            if title_services(r.get('name',''),r.get('title','')): chosen.add(i)
        for i,r in j.get('npcs',{}).items():
            if set(r.get('interactions',[])) & INTERACTIONS.keys(): chosen.add(i)
        chosen.update(j.get('vendors',{}))
        for coll in ('objects','approached'):
            for i,r in j.get(coll,{}).items():
                if r.get('name') in ('Mailbox','Meeting Stone'): objects.add(i)
    files={}
    keys={'creatures': ['name','title','reactions'], 'npcs':['name','side','interactions','positions','lastSeen'],
          'vendors':['name','repairs','positions','lastSeen'], 'objects':['name','type','side','interactions','positions','lastSeen'],
          'approached':['name','positions']}
    for p in paths:
        if p.name not in ('creature_details.enUS.json','creatures.json','npcs.json','vendors.json','object_details.enUS.json'):continue
        j=json.loads(p.read_text()); collections={}
        for coll,fields in keys.items():
            rows={i:{k:r[k] for k in fields if k in r} for i,r in j.get(coll,{}).items() if i in (objects if coll in ('objects','approached') else chosen)}
            if rows: collections[coll]=rows
        if collections:
            data=p.read_bytes()
            files[p.relative_to(eg).as_posix()]={'sha256':hashlib.sha256(data).hexdigest(),
                'git_blob':hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest(),
                'meta':j['meta'],'collections':collections}
    # ATT Camelot's explicit NPC coordinate literal. No quest-provider or
    # containing-zone position is ever substituted for an NPC coordinate.
    attfiles={}
    for p in sorted((att/'db/Camelot').rglob('*.lua')):
        text=p.read_text(encoding='utf-8-sig');records=[]
        for m in re.finditer(r'\bn\((\d+),\{coords=',text):
            if m[1] not in chosen:continue
            start=m.end();literal,end=balanced(text,start)
            # r is ATT's explicit restriction: 1 Horde, 2 Alliance.
            restriction=re.match(r',r=([12])(?:,|\})',text[end:])
            records.append({'id':int(m[1]),'line':text.count('\n',0,m.start())+1,
                            'literal':text[m.start():end], 'restriction':int(restriction[1]) if restriction else 0})
        if records:
            data=p.read_bytes();canonical=data.replace(b'\r\n',b'\n')
            attfiles[p.relative_to(att).as_posix()]={'sha256':hashlib.sha256(data).hexdigest(),
                'git_blob':hashlib.sha1(b'blob '+str(len(canonical)).encode()+b'\0'+canonical).hexdigest(),
                'archive_line_endings':'CRLF' if b'\r\n' in data else 'LF','records':records}
    return {'eg':{'commit':EG_PIN,'files':files},'att':{'commit':ATT_PIN,'files':attfiles}}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('eg',type=Path);ap.add_argument('att',type=Path)
    ap.add_argument('--output',type=Path,default=ROOT/'tools/fixtures/services/evidence.json')
    ap.add_argument('--pfquest',type=Path,help='also pin the complete base-service roster/spawns from this checkout')
    a=ap.parse_args()
    j=extract(a.eg,a.att);a.output.write_text(json.dumps(j,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
    print('Evidence files:',len(j['eg']['files']),len(j['att']['files']))
    if a.pfquest:
        lua=os.environ.get('LUA51') or shutil.which('lua5.1')
        if not lua:raise ValueError('Lua 5.1 is required for sandboxed pfQuest table reading')
        result=subprocess.run([lua,str(ROOT/'tools/extract_service_roster.lua'),str(a.pfquest)],capture_output=True,text=True,check=True)
        files={}
        for name in ['db/units.lua','db/objects.lua','db/enUS/units.lua','db/enUS/objects.lua','db/meta.lua']:
            data=(a.pfquest/name).read_bytes()
            files[name]={'sha256':hashlib.sha256(data).hexdigest(),
                         'git_blob':hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()}
        fixture={'commit':'104f35678ca39ab1fb78b655f815cc7016f5e0c8','files':files,'roster':json.loads(result.stdout)}
        (a.output.parent/'pfquest-roster.json').write_text(json.dumps(fixture,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
if __name__=='__main__':main()
