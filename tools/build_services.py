#!/usr/bin/env python3
"""Generate precise, lazy base-service observations from pinned evidence.

Only the marked supplement in the existing Forever.lua is owned here. The
community WTL1 block and trainer output are preserved byte-for-byte. This
separate compact format avoids WTL1's integer-thousandth precision loss.
"""
import argparse
import csv
import json
import math
import re
from collections import defaultdict
from pathlib import Path
from extract_services import EG_PIN, ATT_PIN, INTERACTIONS, title_services
from service_maps import tables, read_csv

ROOT=Path(__file__).resolve().parents[1]
FIXTURE=ROOT/'tools/fixtures/services/evidence.json'
OUTPUT=ROOT/'WaypointTracker_Data/Forever.lua'
START='-- BEGIN GENERATED BASE SERVICES (tools/build_services.py)\n'
END='-- END GENERATED BASE SERVICES\n'
SERVICES=set('mailbox innkeeper flight repair vendor banker auctioneer stablemaster spirithealer battlemaster meetingstone'.split())

def pf_services():
    text=(ROOT/'tools/fixtures/services/pfquest-meta.lua').read_text()
    out=defaultdict(dict)
    for m in re.finditer(r'^  \["(\w+)"\] = \{(.*?)\n  \}',text,re.S|re.M):
        if m[1] in SERVICES:
            for i,f in re.findall(r'\[(-?\d+)\] = "([AH]*)"',m[2]):out[m[1]][int(i)]=f
    return out

def derive(evidence=None):
    j=evidence or json.loads(FIXTURE.read_text());assert j['eg']['commit']==EG_PIN and j['att']['commit']==ATT_PIN
    maps,_=tables(); latest={}; snapshots=defaultdict(list); reaction={}; object_snaps=defaultdict(list)
    files=sorted(j['eg']['files'].items(),key=lambda kv:(tuple(map(int,kv[1]['meta']['clientBuild'].split('.'))),kv[1]['meta']['product']=='wowf',kv[0]))
    for path,f in files:
        assert re.fullmatch(r'[0-9a-f]{64}',f['sha256'])
        assert f['meta']['license']=='CC BY 4.0'
        for coll,records in f['collections'].items():
            for i,r in records.items():
                ref={'path':path,'collection':coll,'id':i}
                latest[(Path(path).name,coll,i)]=(r,ref)
                if coll=='creatures' and Path(path).name=='creatures.json':
                    for side,values in r.get('reactions',{}).items():reaction[(i,side)]=(values,ref)
                if r.get('positions'):
                    (object_snaps if coll in ('objects','approached') else snapshots)[i].append((r,ref))
    pf=pf_services();basefac={i:f for s,rows in pf.items() for i,f in rows.items() if i>0}
    npcs={i for _,c,i in latest if c in ('creatures','npcs','vendors')}
    out=[];rejected=[]
    def positions(records,multi=False):
        seen=set();result=[]
        for r,ref in reversed(records if multi else records[-1:]):
            for index,p in enumerate(r.get('positions',[])):
                mid=p.get('uiMap');x,y=p.get('mapX'),p.get('mapY')
                if mid not in maps or maps[mid]['mapType'] not in (2,3,6) or not isinstance(x,(int,float)) or not isinstance(y,(int,float)) or not (0<=x<=1 and 0<=y<=1) or not math.isfinite(x+y):
                    rejected.append({'reason':'position has no supported outdoor Forever map','source':ref,'position':p});continue
                if p.get('instance')!=maps[mid]['cont']:
                    rejected.append({'reason':'instance differs from pinned client map','source':ref,'position':p});continue
                # Identical observations deduplicate; nearby literal points
                # remain distinct because object IDs can have many spawns.
                cell=(mid,x,y)
                if cell in seen:continue
                seen.add(cell);result.append({'m':mid,'x':x,'y':y,'c':maps[mid]['cont'],'source':dict(ref,index=index)})
        return sorted(result,key=lambda p:(p['m'],p['x'],p['y']))
    for i in sorted(npcs,key=int):
        title,tref=latest.get(('creature_details.enUS.json','creatures',i),({},None))
        npc,nref=latest.get(('npcs.json','npcs',i),({},None))
        vendor,vref=latest.get(('vendors.json','vendors',i),({},None))
        name=title.get('name') or npc.get('name') or vendor.get('name','')
        svc=title_services(name,title.get('title',''));proof={s:tref for s in svc}
        for v in npc.get('interactions',[]):
            if v in INTERACTIONS:svc.add(INTERACTIONS[v]);proof[INTERACTIONS[v]]=nref
        if vref:svc.add('vendor');proof['vendor']=vref
        if vendor.get('repairs') is True:svc.add('repair');proof['repair']=vref
        if not svc:continue
        side=npc.get('side');fac={'Alliance':'A','Horde':'H'}.get(side,'');fref=nref if fac else None
        if not fac and int(i) in basefac:fac=basefac[int(i)];fref={'pfquest':int(i)}
        if not fac:
            # Reactions alone do not prove a service window is usable (class
            # and reputation gates can coexist with a neutral/friendly NPC).
            witnessed={INTERACTIONS[v] for v in npc.get('interactions',[]) if v in INTERACTIONS}
            if vref:witnessed.add('vendor')
            if vendor.get('repairs') is True:witnessed.add('repair')
            svc &= witnessed
            if not svc:
                rejected.append({'kind':'N','id':int(i),'name':name,'reason':'no witnessed service interaction for reaction-based access'})
                continue
            refs=[]
            for side,letter in [('Alliance','A'),('Horde','H')]:
                values,ref=reaction.get((i,side),([],None))
                if values and all(isinstance(v,(int,float)) and 4<=v<=8 for v in values):fac+=letter;refs.append(ref)
            fref=refs
        pts=positions(snapshots[i],multi=(i=='6491'))
        if not fac:
            rejected.append({'kind':'N','id':int(i),'name':name,'services':sorted(svc),'reason':'unknown faction access','points':pts});continue
        out.append({'kind':'N','id':int(i),'name':name,'fac':fac,'services':sorted(svc),'proof':proof,'access':fref,'positions':pts,'mode':'M' if i=='6491' else 'R'})
    # ATT coordinates only supplement an explicitly evidenced service identity
    # with no Forever interaction coordinates. No title/role is inferred here.
    byid={r['id']:r for r in out}
    for path,f in sorted(j['att']['files'].items()):
        assert re.fullmatch(r'[0-9a-f]{64}',f['sha256'])
        for index,r in enumerate(f['records']):
            row=byid.get(r['id'])
            if not row or row['positions']:continue
            pts=[]
            for mid,body in re.findall(r'\[(\d+)\]=\{(.*?)\}(?=,?\[|\}$)',r['literal'].split('coords=',1)[1],re.S):
                mid=int(mid)
                if mid not in maps:continue
                for x,y in re.findall(r'\{([\d.]+),([\d.]+)\}',body):
                    x,y=float(x)/100,float(y)/100
                    if 0<=x<=1 and 0<=y<=1:pts.append({'m':mid,'x':x,'y':y,'c':maps[mid]['cont'],'source':{'att':path,'record':index}})
            row['positions']=pts
    area={int(r['ID']):r for r in read_csv(ROOT/'tools/fixtures/client/AreaTable-1.60.1.70862-enUS.csv')}
    assignments=read_csv(ROOT/'tools/fixtures/client/UiMapAssignment-1.60.1.70862-enUS.csv')
    masks={int(r['UiMapID']):area.get(int(r['AreaID']),{}).get('FactionGroupMask','0') for r in assignments if int(r['AreaID'])}
    for i in sorted(object_snaps,key=int):
        records=object_snaps[i];name=records[-1][0].get('name','')
        if name not in ('Mailbox','Meeting Stone'):continue
        service='mailbox' if name=='Mailbox' else 'meetingstone';pts=positions(records,multi=True);groups=defaultdict(list)
        for p in pts:
            fac=pf[service].get(-int(i))
            access={'pfquest':-int(i)} if fac else None
            if not fac:
                mid=p['m']
                if maps[mid]['mapType']==2:
                    # A continent-map observation still has an exact literal
                    # position. Resolve only its access area using real bounds;
                    # do not replace or round its source coordinates.
                    m=maps[mid];wx=m['top']-p['y']*m['h'];wy=m['left']-p['x']*m['w']
                    zones=[z for z in maps.values() if z['mapType']==3 and z['cont']==m['cont']
                           and 0<=(z['left']-wy)/z['w']<=1 and 0<=(z['top']-wx)/z['h']<=1]
                    if zones:mid=min(zones,key=lambda z:(z['w']*z['h'],z['mapID']))['mapID']
                mask=masks.get(mid,'0');fac={'2':'A','4':'H'}.get(mask,'AH')
                access={'client_area_faction_mask':mask,'map':mid}
            groups[fac].append(dict(p,access=access))
        for fac,points in sorted(groups.items()):
            out.append({'kind':'O','id':int(i),'name':name,'fac':fac,'services':[service],'proof':{service:records[-1][1]},'positions':points,'mode':'M'})
    for row in out:
        assert row['name'] and ']==]' not in row['name'] and not any(c in row['name'] for c in '\t\n\r')
        assert set(row['services'])<=SERVICES and row['fac'] in ('A','H','AH')
    return sorted(out,key=lambda r:(r['kind'],r['id'],r['fac'])),rejected

def block(rows):
    lines=[]
    for r in rows:
        spots=';'.join('%s:%s,%s,%s'%(p['m'],repr(p['x']),repr(p['y']),p['c']) for p in r['positions'])
        lines.append('\t'.join(['S'+r['kind'],str(r['id']),r['fac'],r['name'],','.join(r['services']),r['mode'],spots]).rstrip('\t'))
    return START+'-- Community observations; precise coordinates, never personal discoveries.\nWaypointTrackerData.serviceSupplement = [==[\n'+'\n'.join(lines)+'\n]==]\n'+END

def generate(text,rows):
    body=block(rows)
    if START in text:
        before,tail=text.split(START,1);_,after=tail.split(END,1);return before+body+after
    return text.rstrip()+'\n\n'+body

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--check',action='store_true');ap.add_argument('--report',type=Path);a=ap.parse_args()
    rows,rejected=derive();original=OUTPUT.read_text();result=generate(original,rows)
    if a.report:a.report.write_text(json.dumps({'rows':rows,'rejected':rejected},ensure_ascii=False,indent=2)+'\n')
    if a.check:
        if result!=original:raise SystemExit('FAIL stale generated base services; run tools/build_services.py')
    else:OUTPUT.write_text(result)
    print('Base services:',len(rows),'identities/access groups;',sum(len(r['positions']) for r in rows),'precise observations;',len(rejected),'rejections')
if __name__=='__main__':main()
