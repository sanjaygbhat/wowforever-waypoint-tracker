#!/usr/bin/env python3
"""Create a new, reviewable recovery package from saved source evidence. Never apply.
Usage: python3 tools/nonroutable_v2/build_package.py EVIDENCE_DIR RAW_POSITION_JSON OUTPUT_DIR [COMPILED_POSITION_JSONL]
"""
import collections,csv,hashlib,json,re,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
E=json.load(open(Path(sys.argv[1])/'target-evidence.json'));P=json.load(open(sys.argv[2]));out=Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=False)
W=json.load(open(HERE/'web-confirmations.json'))['definitions']
rows=list(csv.reader((l for l in (HERE/'input.tsv').read_text().splitlines() if not l.startswith('#')),delimiter='\t'))
ui={int(r['ID']):r for r in csv.DictReader(open(ROOT/'tools/fixtures/client/UiMap-1.60.1.70338-enUS.csv'))}
unresolved={
 'O100000000':'Only a generic LocalizationDB label (Sentinax Portal); no typed Classic/Forever entity record connecting this number to Q65602. Identity/namespace and position unresolved; do not substitute a quest area.',
 'O100000001':'Only a generic LocalizationDB label (Unlit Torch); no typed Classic/Forever entity record connecting this number to I190308. Identity/namespace and position unresolved.',
 'O668493':'Raw author explicitly calls this an unnamed object giving a Gnarlpine Totem. No verified display name or unique source position; multiple providers share the quest objective.',
 'Q97267':'Exact StartQuestID is present on I275985 in build-70338 ItemSparse, but absent from build-70338 QuestV2 and pinned ATT quest names; Wowhead query unavailable/no matching result. Retain original start-quest link.'}
positions=collections.defaultdict(list)
for p in P['evidence']:
 for c in p['coords']:
  assert c['map'] in ui and 0<=c['x']<=100 and 0<=c['y']<=100,(p['target'],c)
 positions[p['target']].append(p)
# This inactive beta provider is named explicitly; it receives NO coordinate or functional claim.
cache=Path(json.load(open(HERE/'baseline.json'))['source_cache'])/'ATT'
skypath=cache/'.contrib/.db/forever/zones/zephras isle.lua';skyline=291
skyraw=skypath.read_text().splitlines()[skyline-1]
assert '251314' in skyraw and 'Skyhopper' in skyraw
E['U251314']['hits']=[dict(name='Skyhopper',path=str(skypath.relative_to(cache)),line=skyline,raw=skyraw,scope='forever',method='inactive-provider-comment',sha256=hashlib.sha256(skypath.read_bytes()).hexdigest(),url='https://github.com/ATTWoWAddon/AllTheThings/blob/ec1aa307198d92d18c601ae2c9338a67b71e7d6b/'+str(skypath.relative_to(cache))+'#L291')]
resolved={}
for t,e in E.items():
 if t in unresolved:continue
 hits=e['hits']
 # Exact typed localization names win over object comments. Preserve upstream spelling.
 loc=[h for h in hits if h['method']=='ObjectNames']
 selected=(loc or hits)[0] if hits else None
 if t in W:
  name=W[t]['name'];source=W[t]
 else:
  assert selected,t;name=selected['name'];source=selected
 scope=selected['scope'] if selected else 'wowhead-classic-family'
 pts=[];pos_sources=[]
 for p in positions[t]:
  if p not in pos_sources:pos_sources.append(p)
  for c in p['coords']:
   tup=(c['map'],round(c['x']*10),round(c['y']*10))
   if tup not in pts:pts.append(tup)
 pts.sort();spots=[]
 for mid in sorted({p[0] for p in pts}):
  nums=[str(v) for p in pts if p[0]==mid for v in p[1:]];spots.append(str(mid)+':'+','.join(nums))
 resolved[t]=dict(name=name,source=source,scope=scope,spots=';'.join(spots),position_sources=pos_sources,name_alternatives=sorted({h['name'] for h in hits}),status='CONFIRMED_POSITION' if pts else 'CONFIRMED_DEFINITION_ONLY',location_status='Sourced Forever target/hunting location; not an in-game survey' if pts else 'UNRESOLVED: no exact Forever target location',relationship_count=sum((r[3] if not r[3].isdigit() else 'Q'+r[3])==t for r in rows))
lines=['WTL1\tatt-source-recovery-v2\t1'];comments=[]
for t,d in sorted(resolved.items(),key=lambda x:(x[0][0],int(x[0][1:]))):
 kind='N' if t[0]=='U' else t[0];i=t[1:];name=d['name'];spot=d['spots']
 assert not any(c in name for c in '\t\r\n')
 fields={'N':['N',i,name,'','','',spot,''],'O':['O',i,name,spot],'I':['I',i,name,'',''],'Q':['Q',i,name,'','','','','','','','']}[kind]
 lines.append('\t'.join(fields));comments.append('-- '+t+' '+d['status']+' '+d['source']['url'])
 for p in d['position_sources']:comments.append('-- '+t+' POSITION '+p['url'])
body='\n'.join(lines)+'\n';assert ']==]' not in body
lua='-- Source-backed recovery for the 531 audited relationships. MIT ATT sources.\n-- Append after the original Curated.lua payload; no new runtime code or TOC entry needed.\n-- Names alone never establish a spawn, accessibility, or relationship validity.\n'+'\n'.join(comments)+'\nlocal D = WaypointTrackerData\nif not D then return end\nlocal sourceRecoveryV2 = [==[\n'+body+']==]\nD.curated = (D.curated or "") .. "\\n" .. sourceRecoveryV2\n'
(out/'SourceRecovery.lua').write_text(lua)
(out/'definitions.json').write_text(json.dumps(resolved,indent=2,ensure_ascii=False)+'\n')
(out/'target-evidence.json').write_text(json.dumps(E,indent=2,ensure_ascii=False)+'\n')
(out/'raw-position-evidence.json').write_text(json.dumps(P,indent=2,ensure_ascii=False)+'\n')
if len(sys.argv)>4:
 (out/'compiled-position-leads.jsonl').write_bytes(Path(sys.argv[4]).read_bytes())
(out/'source-hashes.json').write_bytes((Path(sys.argv[1])/'source-hashes.json').read_bytes())
ledger=[];exceptions=[]
for r in rows:
 t=r[3] if not r[3].isdigit() else 'Q'+r[3]
 if t in unresolved:
  status='UNRESOLVED_IDENTITY';why=unresolved[t];name='';url='https://wago.tools/db2/ItemSparse?build=1.60.1.70338' if t.startswith('Q') else 'https://github.com/ATTWoWAddon/AllTheThings/tree/ec1aa307198d92d18c601ae2c9338a67b71e7d6b/db/Camelot'
  exceptions.append('\t'.join(r[:4]+[why]))
 else:
  d=resolved[t];status=d['status'];why=d['location_status'];name=d['name'];url=d['source']['url']
  if t=='U251314':why+='; raw provider commented out because beta gave no quest credit'
  if t=='U251247':why+='; raw author explicitly says location unknown'
  if t=='O673399':why+='; conflicting provider comment Meat Haunch versus localized Stolen Weapon; quest-link correctness unresolved'
 giver=r[0].endswith(':giver');score=(100 if giver else 0)+20*sum((rr[3] if not rr[3].isdigit() else 'Q'+rr[3])==t for rr in rows)+(40 if status=='CONFIRMED_POSITION' else 0)
 ledger.append([score,status,*r[:4],t,name,why,url])
ledger.sort(key=lambda r:(-r[0],r[6],r[4]))
with (out/'relationships.tsv').open('w') as f:
 writer=csv.writer(f,delimiter='\t',lineterminator='\n');writer.writerow(['priority_score','status','category','file','entry','original_target','typed_target','name','location_reason','source_url']);writer.writerows(ledger)
(out/'remaining_exceptions.tsv').write_text('# Exact unresolved identity relationships after applying SourceRecovery.lua.\n# category\tfile\tentry\ttarget\treason\n'+'\n'.join(exceptions)+'\n')
with (out/'unresolved_locations.tsv').open('w') as f:
 writer=csv.writer(f,delimiter='\t',lineterminator='\n');writer.writerow(['target','name','relationships','reason','source_url'])
 for t,d in sorted(resolved.items()):
  if not d['spots']:writer.writerow([t,d['name'],d['relationship_count'],next(r[8] for r in ledger if r[6]==t),d['source']['url']])
 for t,why in unresolved.items():writer.writerow([t,'',sum(r[6]==t for r in ledger),why,next(r[9] for r in ledger if r[6]==t)])
summary=dict(input_relationships=len(rows),input_targets=len(E),definitions=len(resolved),definition_kinds=dict(collections.Counter(t[0] for t in resolved)),relationships=dict(collections.Counter(r[1] for r in ledger)),position_targets=sum(bool(d['spots']) for d in resolved.values()),points=sum(len({(c['map'],c['x'],c['y']) for p in d['position_sources'] for c in p['coords']}) for d in resolved.values()),unresolved_identity_targets=len(unresolved),remaining_exception_rows=len(exceptions))
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
