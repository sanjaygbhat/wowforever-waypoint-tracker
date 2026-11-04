#!/usr/bin/env python3
"""Extract same-table coordinate evidence from raw ATT source, never inheriting spots.
Read-only. Output JSON on stdout. Sources with unknown map symbols are retained as leads.
"""
import sys,json,re,hashlib
from pathlib import Path
base=Path(sys.argv[1]); evidence=json.load(open(sys.argv[2]));targets=set(evidence)
mapfile=base/'.contrib/.db/forever/.config/constants/maps.lua'
maps={m[1]:int(m[2]) for m in re.finditer(r'^\s*([A-Z][A-Z_0-9]+)\s*=\s*(\d+)',mapfile.read_text(),re.M)}
# Mask comments and string literals but preserve offsets and quoted field contents.
token=re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]',re.S)
out=[]
for p in sorted((base/'.contrib/.db/forever').rglob('*.lua')):
 if '/.config/' in str(p) or '/zzOLD/' in str(p):continue
 text=p.read_text(); masked=list(text);stack=[];nodes=[]
 for m in token.finditer(text):
  v=m[0]
  if v=='{':
   node={'start':m.start(),'children':[]};
   if stack:stack[-1]['children'].append(node)
   stack.append(node)
  elif v=='}':
   if stack:node=stack.pop();node['end']=m.end();nodes.append(node)
  elif v.startswith('--') or v.startswith('['):
   masked[m.start():m.end()]=['\n' if c=='\n' else ' ' for c in v]
  # Strings cannot create braces. Preserve quoted keys, mask other content.
  elif v.startswith(('"',"'")) and v.strip('"\'') not in ['n','o','i','q','qg','cr','crs','provider','providers','coord','coords']:
   masked[m.start():m.end()]=[' ']*len(v)
 clean=''.join(masked)
 for node in nodes:
  start,end=node['start'],node['end'];body=list(clean[start:end])
  children=node['children']
  for c in children:body[c['start']-start:c['end']-start]=[' ']*(c['end']-c['start'])
  own=''.join(body); refs={}
  for m in re.finditer(r'(?<!\w)(?:\["(qg|cr)"\]|(qg|cr))\s*=\s*(\d+)',own):
   target='U'+m[3]
   if target in targets:refs[target]='same-table-'+(m[1] or m[2])
  prefix=clean[max(0,start-100):start]
  ctor=re.search(r'\b([no])\(\s*(\d+)\s*,\s*$',prefix)
  if ctor:
   target=('U' if ctor[1]=='n' else 'O')+ctor[2]
   if target in targets:refs[target]='direct-entity'
  coordnodes=[]
  for c in children:
   lead=clean[max(start,c['start']-50):c['start']]
   if re.search(r'(?:\["coords?"\]|\bcoords?)\s*=\s*$',lead):coordnodes.append(c)
   # A singular provider + same-table coords links one explicit object/NPC.
   if re.search(r'(?:\["provider"\]|\bprovider)\s*=\s*$',lead):
    m=re.fullmatch(r'\{\s*"([no])"\s*,\s*(\d+)\s*\}',clean[c['start']:c['end']])
    if m:
     target=('U' if m[1]=='n' else 'O')+m[2]
     if target in targets:refs[target]='same-table-single-provider'
  if not refs or not coordnodes:continue
  coords=[]
  for c in coordnodes:
   part=clean[c['start']:c['end']]
   for m in re.finditer(r'\{\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*(MAP\.[A-Z_0-9]+|[A-Z_0-9]+|\d+)\s*\}',part):
    mapkey=m[3];mid=int(mapkey) if mapkey.isdigit() else maps.get(mapkey.removeprefix('MAP.'))
    coords.append({'map':mid,'symbol':mapkey,'x':float(m[1]),'y':float(m[2])})
  if not coords:continue
  rel=str(p.relative_to(base));line=text.count('\n',0,start)+1
  for target,method in refs.items():
   out.append(dict(target=target,method=method,coords=coords,path=rel,line=line,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),raw=text[start:end],url='https://github.com/ATTWoWAddon/AllTheThings/blob/ec1aa307198d92d18c601ae2c9338a67b71e7d6b/'+rel+'#L'+str(line)))
print(json.dumps({'map_constants_source':str(mapfile.relative_to(base)),'map_constants_sha256':hashlib.sha256(mapfile.read_bytes()).hexdigest(),'evidence':out},indent=2,ensure_ascii=False))
