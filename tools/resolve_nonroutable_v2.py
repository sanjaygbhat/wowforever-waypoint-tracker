#!/usr/bin/env python3
"""Read-only source investigation. Creates a new output directory, never replaces files.
Usage: python3 tools/resolve_nonroutable_v2.py --cache /path/datarefresh --out /tmp/new-dir
Outputs evidence for every target, with typed source citations and source hashes.
"""
import argparse,collections,csv,hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
COMMIT='ec1aa307198d92d18c601ae2c9338a67b71e7d6b'

def tidy(s):
    s=re.sub(r'<[^>]*>?','',s)
    s=re.sub(r'\s*\[.*?\]','',s)
    s=re.sub(r'\s*\([^)]*\)\s*$','',s)
    s=re.sub(r'\s+',' ',s).strip()
    return s

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--cache',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    a.out.mkdir(parents=True,exist_ok=False)
    rows=list(csv.reader((l for l in (ROOT/'tools/nonroutable_v2/input.tsv').read_text().splitlines() if not l.startswith('#')),delimiter='\t'))
    targets={r[3] if not r[3].isdigit() else 'Q'+r[3] for r in rows}
    hits=collections.defaultdict(list);filehash={}
    def add(target,name,path,line,raw,scope,method):
        if target not in targets or not name or not name.strip():return
        name=tidy(name)
        if not name or name.startswith(('TODO','???')):return
        rel=str(path.relative_to(a.cache/'ATT'));sha=filehash.setdefault(rel,hashlib.sha256(path.read_bytes()).hexdigest())
        hits[target].append(dict(name=name,path=rel,line=line,raw=raw,scope=scope,method=method,sha256=sha,url='https://github.com/ATTWoWAddon/AllTheThings/blob/'+COMMIT+'/'+rel+'#L'+str(line)))
    # Source order is important: current Forever first, then old Forever, then Standard.
    src=a.cache/'ATT/.contrib/.db'
    paths=sorted((src/'forever').rglob('*.lua'),key=lambda p:('zzOLD' in str(p),str(p)))+sorted((src/'standard').rglob('*.lua'))
    ctor=re.compile(r'(?<![\w])([noiq])\(\s*(\d+)\s*[,)]')
    provider=re.compile(r'\{\s*"([noiq])"\s*,\s*(\d+)\s*[,}]')
    key=re.compile(r'(?<![\w])(?:\["?(qg|cr|npcID|creatureID|objectID|itemID|questID)"?\]|(qg|cr|npcID|creatureID|objectID|itemID|questID))\s*=\s*(\d+)')
    trans={'n':'U','o':'O','i':'I','q':'Q'}
    for p in paths:
        scope='forever-old' if '/zzOLD/' in str(p) else 'forever' if '/forever/' in str(p) else 'standard'
        crs=False
        for lineno,line in enumerate(p.read_text(errors='replace').splitlines(),1):
            if '--' not in line:
                if re.search(r'(?:"crs"|\bcrs)\s*\]?\s*=\s*{',line):crs=True
                elif crs and '}' in line:crs=False
                continue
            code,comment=line.split('--',1)
            for m in ctor.finditer(code):add(trans[m[1]]+m[2],comment,p,lineno,line,scope,'typed-constructor-comment')
            for m in provider.finditer(code):add(trans[m[1]]+m[2],comment,p,lineno,line,scope,'typed-provider-or-cost-comment')
            for m in key.finditer(code):
                field=m[1] or m[2]
                kind='U' if field in ('qg','cr','npcID','creatureID') else {'objectID':'O','itemID':'I','questID':'Q'}[field]
                add(kind+m[3],comment,p,lineno,line,scope,'typed-key-comment')
            if re.search(r'(?:"crs"|\bcrs)\s*\]?\s*=\s*{',code):crs=True
            if crs:
                m=re.match(r'\s*(\d+)\s*,?\s*$',code)
                if m:add('U'+m[1],comment,p,lineno,line,scope,'crs-member-comment')
                if '}' in code:crs=False
    for version in ['Camelot','VanillaSOD','Vanilla']:
        p=a.cache/'ATT/db'/version/'LocalizationDB.lua'
        text=p.read_text();start=text.find('local ObjectNames =');end=text.find('\n}',start)
        for m in re.finditer(r'\[(\d+)\]\s*=\s*"([^"\n]+)"',text[start:end]):
            line=text.count('\n',0,start+m.start())+1
            add('O'+m[1],m[2],p,line,text.splitlines()[line-1],version,'ObjectNames')
    # Full cached Wago tables supplement the reduced in-repo tables.
    client={r['ID']:r for r in csv.DictReader(open(a.cache/'wago/cache/ItemSparse-1.60.1.70338-enUS.csv'))}
    roster={r['ID'] for r in csv.DictReader(open(ROOT/'tools/fixtures/client/QuestV2-1.60.1.70338-enUS.csv'))}
    pf=subprocess.check_output(['lua',str(ROOT/'tools/nonroutable_v2/extract_pfquest.lua'),str(a.cache/'pfQuest'),str(ROOT/'tools/nonroutable_v2/input.tsv')],text=True)
    pfrows={r[0]:dict(name=r[1],coords=r[2],definition=r[3]) for r in csv.reader(pf.splitlines(),delimiter='\t')}
    evidence={t:dict(hits=hits[t],pfquest=pfrows[t],client_item=client.get(t[1:]) if t.startswith('I') else None,client_quest=t[1:] in roster if t.startswith('Q') else None) for t in sorted(targets)}
    (a.out/'target-evidence.json').write_text(json.dumps(evidence,indent=2,ensure_ascii=False)+'\n')
    (a.out/'source-hashes.json').write_text(json.dumps(filehash,indent=2)+'\n')
    print('targets',len(targets),'ATT named',sum(bool(e['hits']) for e in evidence.values()),'pf names',sum(bool(e['pfquest']['name']) for e in evidence.values()))
    for t,e in evidence.items():
        names=set(h['name'] for h in e['hits'])
        if len(names)>1: print('NAME-CONFLICT',t,sorted(names))
    print('unnamed',[t for t,e in evidence.items() if not e['hits'] and not e['pfquest']['name']])
if __name__=='__main__':main()
