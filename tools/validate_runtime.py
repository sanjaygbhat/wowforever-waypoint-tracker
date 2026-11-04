#!/usr/bin/env python3
"""Offline Lua runtime audit; run from any directory with python3.

No dependencies, no execution of addon code, no network. This is a conservative
lexical checker, NOT a full Lua dataflow proof. It rejects unreviewed API return
boundaries; inspect findings rather than assuming every finding crashes in game.
Subcommands: secrets, glyphs, registrations, api, all, selftest.
API evidence is read from the adjacent validate_runtime_api.json manifest.
Optional --font LOCALE=/path/to/font.ttf checks actual Unicode cmap coverage
(standard library parser, TTF/OTF cmap formats 4 and 12).
Optional --reviews JSON reports explicitly reviewed, unconfirmed secret findings
without failing them. Matches require exact file, API and source line; new,
changed, duplicate or stale reviews fail. Raw mode still reports every finding.
"""
import argparse
import collections
import dataclasses
import json
from pathlib import Path
import re
import struct
import sys
import unicodedata

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
BUILD = '1.60.1.70338'
SOURCE = 'https://github.com/Gethe/wow-ui-source/tree/943764493e6b16d63ded3ab304150d1f05e58b57'
# SecretReturns / SecretWhen... in the exact build's UnitDocumentation.lua.
# Numeric position/facing/level are also required by the audit policy, even
# where generated docs do not explicitly promise secret returns.
NUMERIC = set('GetUnitSpeed UnitPosition GetPlayerFacing UnitLevel UnitHealth UnitHealthMax UnitPower UnitPowerMax UnitDistanceSquared GetUnitHealthPercent GetSpellCooldown'.split())
IDENTITY = set('UnitName UnitFullName UnitGUID UnitNameUnmodified UnitNameFromGUID GetUnitName UnitClass UnitRace'.split())
EXTRA_SECRET = set('UnitIsCharmed UnitIsPossessed UnitIsUnit UnitCastingInfo UnitChannelInfo'.split())
SENSITIVE = NUMERIC | IDENTITY | EXTRA_SECRET
SAFE = {'ns.Num', 'Num', 'ns.Plain', 'Plain', 'ns.Str', 'Str', 'issecretvalue', 'canaccessvalue'}
TRANSFORMS = {'tonumber', 'tostring', 'ns.Int', 'Int', 'math.deg', 'math.floor', 'math.max', 'math.min', 'select'}

@dataclasses.dataclass
class Token:
    value: str
    line: int
    kind: str = 'code'
    offset: int = 0

def decode_string(raw):
    data = bytearray()
    i = 0
    escapes = {'a':7, 'b':8, 'f':12, 'n':10, 'r':13, 't':9, 'v':11}
    while i < len(raw):
        if raw[i] != '\\':
            data.extend(raw[i].encode('utf-8')); i += 1; continue
        i += 1
        if i == len(raw):
            raise ValueError('trailing escape')
        if raw[i].isdigit():
            m = re.match(r'\d{1,3}', raw[i:])
            n = int(m[0])
            if n > 255: raise ValueError('Lua decimal escape exceeds 255')
            data.append(n); i += len(m[0])
        else:
            c = raw[i]; i += 1
            data.extend(bytes([escapes[c]]) if c in escapes else c.encode('utf-8'))
    # Lua byte-pattern literals deliberately contain incomplete UTF-8 bytes.
    # Preserve them for code analysis; glyph checks skip such binary patterns.
    return data.decode('utf-8', errors='surrogateescape')

def lex(text):
    """Skip Lua comments; preserve multiline and escaped strings with line IDs."""
    out, i, line = [], 0, 1
    while i < len(text):
        start, n = i, line
        if text[i].isspace():
            line += text[i] == '\n'; i += 1; continue
        comment = text.startswith('--', i)
        if comment: i += 2
        long = re.match(r'\[(=*)\[', text[i:])
        if long:
            close = ']' + long[1] + ']'
            begin = i + len(long[0]); end = text.find(close, begin)
            if end < 0: raise ValueError(f'line {n}: unclosed long string/comment')
            raw = text[begin:end]
            if raw.startswith('\n'): raw = raw[1:]
            i = end + len(close)
            if not comment: out.append(Token(raw,n,'string',start))
        elif comment:
            end = text.find('\n',i); i = len(text) if end < 0 else end
        elif text[i] in '\"\'':
            quote = text[i]; i += 1; begin = i
            while i < len(text):
                if text[i] == '\\': i += 2
                elif text[i] == quote: break
                else: i += 1
            if i >= len(text): raise ValueError(f'line {n}: unclosed string')
            out.append(Token(decode_string(text[begin:i]),n,'string',start)); i += 1
        else:
            m = re.match(r'[A-Za-z_][A-Za-z_0-9]*|\d+(?:\.\d+)?|\.\.\.|\.\.|==|~=|<=|>=|.',text[i:])
            out.append(Token(m[0],n,'code',start)); i += len(m[0])
        line += text[start:i].count('\n')
    return out

def qualified(ts, i):
    if i < 0: return ''
    parts = [ts[i].value]
    while i >= 2 and ts[i-1].value in ('.', ':'):
        parts[:0] = [ts[i-2].value, ts[i-1].value]; i -= 2
    return ''.join(parts)

def calls(ts):
    stack, result = [], []
    for i,t in enumerate(ts):
        if t.kind == 'string': continue
        if t.value == '(':
            name = qualified(ts,i-1)
            call = {'name':name,'open':i,'line':t.line,'ancestors':list(stack)}
            stack.append(call); result.append(call)
        elif t.value == ')' and stack:
            stack.pop()['close'] = i
    return [c for c in result if 'close' in c]

def failure(path, line, entry, value, why):
    return f'{path}:{line}: {entry}: value={value!r}: {why}'

def sanitized(c):
    # Num(tonumber(secret)) is unsafe; the sanitizer must precede conversion.
    for parent in reversed(c['ancestors']):
        if parent['name'] in SAFE: return True
        if parent['name'] in TRANSFORMS: return False
    return False

def delayed_sanitized(ts, c, skip_status=False):
    """Allow raw multi-return assignment followed immediately by sanitization.

    No broad lookahead: using the value before a later Num must still fail.
    Fields, interprocedural sanitization and control-flow guards need review.
    """
    oi = c['open']
    start = oi - 1
    while start > 0 and ts[start-1].line == ts[oi].line: start -= 1
    lhs = [t.value for t in ts[start:oi-1]]
    if '=' not in lhs: return False
    lhs = lhs[:lhs.index('=')]
    if lhs and lhs[0] == 'local': lhs = lhs[1:]
    if any(v not in {',','_'} and not re.fullmatch(r'\w+',v) for v in lhs): return False
    variables = [v for v in lhs if v != ',']
    if skip_status: variables=variables[1:]
    variables=[v for v in variables if v!='_']
    if not variables: return False
    tail = ts[c['close']+1:]
    if not tail: return False
    nextline = tail[0].line
    stmt = [t for t in tail if t.line == nextline]
    s = ''.join(t.value for t in stmt)
    return all(re.search(r'(?:ns\.)?(?:Num|Plain|Str)\('+re.escape(v)+r'\)',s) for v in variables)

def secrets(path, ts):
    out=[]
    for c in calls(ts):
        if c['name'] in SENSITIVE and not sanitized(c) and not delayed_sanitized(ts,c):
            helper = 'ns.Num' if c['name'] in NUMERIC else 'ns.Plain'
            qualifier = 'numeric audit policy' if c['name'] in {'UnitLevel','UnitPosition','GetPlayerFacing'} else 'potential secret return'
            out.append(failure(path,c['line'],c['name'],c['name']+'(...)',f'{qualifier}; sanitize with {helper} before comparison, conversion, indexing or arithmetic; pcall alone does not sanitize a return'))
        if c['name']=='pcall':
            start=c['open']+1
            end=start
            while end<c['close'] and ts[end].value!=',': end+=1
            callee=''.join(t.value for t in ts[start:end])
            if callee in SENSITIVE and not delayed_sanitized(ts,c,skip_status=True):
                out.append(failure(path,c['line'],callee,'pcall('+callee+', ...)','pcall catches API exceptions; sanitize every data return before use (the first return is only success/failure)'))
    # A cooldown API returns a table whose numeric FIELDS may be secret. Num
    # around the table does not sanitize fields. Include pcall/alias references.
    for i,t in enumerate(ts):
        if t.value=='C_Spell' and i+2<len(ts) and ts[i+1].value=='.' and ts[i+2].value=='GetSpellCooldown':
            if i+3<len(ts) and ts[i+3].value in {'then','and','or'}: continue
            nearby=''.join(t.value for t in ts[i+3:] if t.line <= ts[i].line+5)
            guarded=all(re.search(r'(?:ns\.)?(?:Num|Plain)\(\w+\.'+field+r'\)',nearby) for field in ('startTime','duration'))
            if not guarded:
                out.append(failure(path,t.line,'C_Spell.GetSpellCooldown','startTime/duration','SecretWhenCooldownsRestricted in exact-build SpellDocumentation.lua; sanitize both numeric fields before Ready/arithmetic'))
    return out

def font_cmap(path):
    """Read Unicode cmap format 4/12 without third-party modules."""
    b=Path(path).read_bytes()
    if b[:4] == b'ttcf': raise ValueError('TTC font collections need individual TTF extraction')
    count=struct.unpack_from('>H',b,4)[0]
    offset=None
    for i in range(count):
        tag,_,pos,_=struct.unpack_from('>4sIII',b,12+16*i)
        if tag == b'cmap': offset=pos
    if offset is None: raise ValueError('font has no cmap')
    result=set()
    for i in range(struct.unpack_from('>H',b,offset+2)[0]):
        platform,encoding,sub=struct.unpack_from('>HHI',b,offset+4+8*i)
        if platform != 0 and not (platform==3 and encoding in (1,10)): continue
        p=offset+sub; fmt=struct.unpack_from('>H',b,p)[0]
        if fmt == 12:
            for j in range(struct.unpack_from('>I',b,p+12)[0]):
                lo,hi,glyph=struct.unpack_from('>III',b,p+16+12*j)
                result.update(range(lo+(glyph==0),hi+1))
        elif fmt == 4:
            seg=struct.unpack_from('>H',b,p+6)[0]//2
            end=p+14; start=end+2*seg+2; delta=start+2*seg; ro=delta+2*seg
            for j in range(seg):
                hi=struct.unpack_from('>H',b,end+2*j)[0]; lo=struct.unpack_from('>H',b,start+2*j)[0]
                d=struct.unpack_from('>h',b,delta+2*j)[0]; r=struct.unpack_from('>H',b,ro+2*j)[0]
                for cp in range(lo,hi+1):
                    if cp==65535: continue
                    gid=struct.unpack_from('>H',b,ro+2*j+r+2*(cp-lo))[0] if r else cp
                    if gid and (gid+d)&65535: result.add(cp)
    if not result: raise ValueError('font has no supported Unicode cmap')
    return result

def glyphs(path, ts, fonts):
    out=[]
    locale=path.stem if path.parent.name=='Locales' else re.search(r'_([a-z]{2}[A-Z]{2})$',path.stem)
    if not isinstance(locale,str): locale=locale[1] if locale else '*'
    cmaps = [v for k,v in fonts.items() if k in (locale,'*') or locale=='*']
    for t in ts:
        if t.kind!='string' or any(0xDC80 <= ord(c) <= 0xDCFF for c in t.value): continue
        # These are string literals, not guaranteed UI sinks; names/data can be
        # user visible too. Ignore WoW atlas/texture markup, which is an image.
        s=re.sub(r'\|[TA].*?\|[ta]','',t.value,flags=re.S)
        for ch in sorted(set(s),key=ord):
            cp=ord(ch); category=unicodedata.category(ch)
            # Ordinary Latin-1 signs and Cyrillic numero are locale typography,
            # not decorative symbols. Exact missing coverage requires --font.
            unsafe=(category.startswith('S') and cp>255 and cp!=0x2116) or category in {'Co','Cs','Cf'}
            missing=bool(cmaps) and any(cp not in cmap for cmap in cmaps) and ch not in '\n\t\r'
            if unsafe or missing:
                why='absent from supplied font cmap' if missing else 'portable UI glyph policy: non-ASCII symbol/private/control codepoint; use localized words, ASCII or a WoW texture/atlas (font absence needs cmap/in-game confirmation)'
                out.append(failure(path,t.line,'string literal',f'U+{cp:04X} {ch} {unicodedata.name(ch,"UNNAMED")}',why))
    return out

def registrations(path, ts):
    out=[]; seen={}
    for c in calls(ts):
        name=c['name']
        if name not in {'ns.RegisterEvent','ns.On'} and not name.endswith(':HookScript'): continue
        args=ts[c['open']+1:c['close']]
        if not args or args[0].kind!='string': continue
        # Compare exact callback expressions, not event names alone: different
        # subscribers to one event are intentional, SetScript replaces a slot.
        key=(name,tuple((t.kind,t.value) for t in args))
        if key in seen:
            out.append(failure(path,c['line'],name,args[0].value,f'identical registration also at line {seen[key]}; callback can run twice'))
        seen[key]=c['line']
    return out

def inventory(ts):
    out=set(); defined=set()
    for i,t in enumerate(ts):
        if t.value=='function' and i+1<len(ts) and ts[i+1].value!='(':
            defined.add(ts[i+1].value)
        if t.value=='local':
            for q in ts[i+1:]:
                if q.value in {'=','function'} or q.line!=t.line: break
                if re.fullmatch(r'\w+',q.value): defined.add(q.value)
    for c in calls(ts):
        name=c['name']
        if name.startswith(('C_','Settings.','ChatFrameUtil.','MenuUtil.','TooltipUtil.','EventUtil.','TooltipDataProcessor.','UiMapPoint.')) or (name not in defined and '.' not in name and ':' not in name and re.match(r'(?:Get|Set|Unit|Is|Has|Can|Create|Play|Show|Hide|Toggle|Close|Open|Request|Join|Leave|TakeTaxi|SendAddon|UIParent|ChatFrame_|ChatEdit_|PanelTemplates_|GameTooltip_|StaticPopup_|InterfaceOptions|hooksecurefunc|issecretvalue|canaccessvalue)',name)):
            if c['open']>=2 and ts[c['open']-2].value=='function': continue
            out.add((name,c['line']))
    # Include APIs passed as functions and capability guards; protects alias and
    # pcall use that call-only regex checks miss. All C_ members need reviewing.
    for i,t in enumerate(ts):
        if t.kind=='code' and t.value.startswith('C_') and i+2<len(ts) and ts[i+1].value=='.':
            out.add((t.value+'.'+ts[i+2].value,t.line))
        elif t.kind=='code' and t.value not in defined and re.match(r'^(?:Get[A-Z]|Unit[A-Z]|Is[A-Z]|Can[A-Z]|Create[A-Z]|JoinTemporaryChannel|LeaveChannelByName|TakeTaxiNode|PlaySound|SendAddonMessage|OpenWorldMap|ToggleWorldMap|CloseDropDownMenus|ChatFrame_|ChatEdit_|UIParentLoadAddOn|PanelTemplates_|GameTooltip_|StaticPopup_|InterfaceOptions|issecretvalue|canaccessvalue|hooksecurefunc)',t.value):
            if i and ts[i-1].value in {'.',':','function'}: continue
            if i+2<len(ts) and ts[i+1].value=='=' and ts[i+2].value=='function': continue
            out.add((t.value,t.line))
        if t.kind=='code' and t.value in {'Settings','ChatFrameUtil','MenuUtil','TooltipUtil'} and i+2<len(ts) and ts[i+1].value=='.':
            if i+3<len(ts) and ts[i+3].value=='(': out.add((t.value+'.'+ts[i+2].value,t.line))
    return sorted(out,key=lambda x:(x[1],x[0]))

def api(path,ts,manifest):
    out=[]
    for name,line in inventory(ts):
        row=manifest.get('apis',{}).get(name)
        if row is None:
            out.append(failure(path,line,'API inventory',name,'not in reviewed manifest; establish availability on build '+BUILD+' before use (may be a local helper)'))
        elif row['status']=='optional-guarded':
            # The only reviewed optional globals are old chat aliases and the
            # third-party GetMinimapShape convention. Re-check the guard at each
            # new use, rather than globally allowing an absent function.
            use=[t for t in ts if t.line==line and t.value==name]
            refs=[t for t in ts if t.line in (line,line-1) and t.value==name]
            guard=any(t.value in {'if','elseif','and'} for t in ts if t.line in (line,line-1))
            if len(refs)<2 and use and any(c['name']==name and c['line']==line for c in calls(ts)):
                guard=False
            if not guard:
                out.append(failure(path,line,'optional API guard',name,'reviewed compatibility fallback must stay capability-guarded at every call'))
        elif row['status'] not in {'verified','native-name'}:
            out.append(failure(path,line,'API availability',name,row['status']+': '+row['source']+'; verify on exact client or guard and test fallback; absence from documentation alone does not establish missing API'))
    return out

def selftest():
    tests=[
        (not secrets('sample.lua',lex('local n = ns.Num(GetUnitSpeed("player"))\nif n and n>0 then end')), 'wrapped speed'),
        (bool(secrets('sample.lua',lex('local n=GetUnitSpeed("player")\nif n>0 then end'))),'raw speed'),
        (bool(secrets('sample.lua',lex('local n=ns.Num(tonumber(GetUnitSpeed("player")))'))),'conversion before guard'),
        (not secrets('sample.lua',lex('local s=ns.Str(UnitName("target"))')),'wrapped name'),
        (bool(secrets('sample.lua',lex('local s=ns.Str(tostring(UnitName("target")))'))),'string conversion before guard'),
        (not secrets('sample.lua',lex('local ok,s=pcall(UnitName,"target")\ns=ns.Str(s)')),'pcall string return guarded'),
        (bool(secrets('sample.lua',lex('local ok,n=pcall(GetUnitSpeed,"player")\nif n>0 then end'))),'pcall is not a sanitizer'),
        (not secrets('sample.lua',lex('local ok,n=pcall(GetUnitSpeed,"player")\nn=ns.Num(n)\nif n then end')),'pcall data return guarded'),
        (not secrets('sample.lua',lex('local _, run=GetUnitSpeed("player")\nrun=ns.Num(run)\nif run then end')),'second return guard'),
        (bool(secrets('sample.lua',lex('local _, run=GetUnitSpeed("player")\nif run>0 then end\nrun=ns.Num(run)'))),'guard too late'),
        (not secrets('sample.lua',lex('-- GetUnitSpeed("player")\nlocal s="UnitHealth(1)"')),'comments and strings skipped'),
        (bool(glyphs(Path('sample.lua'),lex('local s="\\226\\150\\178"'),{})),'escaped triangle caught'),
        (bool(glyphs(Path('sample.lua'),lex('local s="✓"'),{})),'literal checkmark caught'),
        (not glyphs(Path('Locales/ruRU.lua'),lex('local s="Русский — é 中文 한국어"'),{}),'letters and punctuation retained'),
        (not glyphs(Path('sample.lua'),lex('-- ▲\nlocal s="|A:some-atlas:16:16|a"'),{}),'comments and atlas skipped'),
        (bool(registrations('sample.lua',lex('ns.On("INIT", cb)\nns.On("INIT", cb)'))),'duplicate subscriber caught'),
        (not registrations('sample.lua',lex('ns.On("INIT", a)\nns.On("INIT", b)')),'independent subscribers allowed'),
        (not registrations('sample.lua',lex('f:SetScript("OnClick", a)\nf:SetScript("OnClick", a)')),'SetScript replacement allowed'),
        (('C_Spell.GetSpellCooldown',1) in inventory(lex('pcall(C_Spell.GetSpellCooldown, 1)')),'pcall reference inventory'),
        (bool(api('sample.lua',lex('C_New.UnknownAPI()'),{'apis':{}})),'unreviewed API rejected'),
        (bool(api('sample.lua',lex('ChatFrame_OpenChat("hi")'),{'apis':{'ChatFrame_OpenChat':{'status':'optional-guarded'}}})),'unguarded legacy alias rejected'),
        (not api('sample.lua',lex('if ChatFrame_OpenChat then\nChatFrame_OpenChat("hi")\nend'),{'apis':{'ChatFrame_OpenChat':{'status':'optional-guarded'}}}),'guarded legacy fallback accepted'),
        (decode_string('\\226\\128\\147')=='–','decimal UTF-8 decoding'),
        (lex('--[=[ ▲ ]=]\n[==[✓]==]')[0].value=='✓','long brackets'),
    ]
    for ok,label in tests:
        if not ok: print('SELFTEST FAIL: '+label)
    print(f'{sum(ok for ok,_ in tests)} passed, {sum(not ok for ok,_ in tests)} failed')
    return int(not all(ok for ok,_ in tests))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('check',choices=['secrets','glyphs','registrations','api','all','selftest'])
    p.add_argument('--root',type=Path,default=ROOT)
    p.add_argument('--font',action='append',default=[],metavar='LOCALE=TTF')
    p.add_argument('--reviews',type=Path,help='explicit unconfirmed secret-return reviews')
    a=p.parse_args()
    if a.check=='selftest': return selftest()
    fonts={}
    for spec in a.font:
        locale,path=spec.split('=',1); fonts[locale]=font_cmap(path)
    manifest_path=Path(__file__).with_name('validate_runtime_api.json')
    manifest=json.loads(manifest_path.read_text()) if a.check in ('api','all') else {}
    reviews = {}
    used_reviews = set()
    if a.reviews:
        if a.check not in ('secrets', 'all'): p.error('--reviews requires secrets or all')
        for row in json.loads(a.reviews.read_text())['reviews']:
            key = (row['file'], row['api'], row['code'])
            if key in reviews or not row.get('reason') or not row.get('source'):
                p.error('duplicate or undocumented secret review: ' + str(key))
            reviews[key] = row
    counts=collections.Counter(); files=0
    for directory in ('WaypointTracker','WaypointTracker_Data'):
        for path in sorted((a.root/directory).rglob('*.lua')):
            files+=1
            rel=path.relative_to(a.root)
            try:
                source_text=path.read_text(encoding='utf-8')
                ts=lex(source_text)
            except (UnicodeError,ValueError) as e:
                print(failure(rel,1,'Lua lexing',str(e),'cannot audit this file')); counts['lex']+=1; continue
            for check in ('secrets','glyphs','registrations','api'):
                if a.check not in (check,'all'): continue
                fn=globals()[check]
                findings=fn(rel,ts,fonts) if check=='glyphs' else fn(rel,ts,manifest) if check=='api' else fn(rel,ts)
                for finding in findings:
                    if check == 'secrets':
                        match = re.match(r'^.*?:(\d+): ([^:]+):', finding)
                        key = (str(rel), match[2], source_text.splitlines()[int(match[1])-1].strip())
                        if key in reviews and key not in used_reviews:
                            used_reviews.add(key)
                            print('REVIEW: ' + finding + '; ' + reviews[key]['reason'])
                            continue
                    counts[check]+=1
                    print(finding)
                counts[check]+=0
    for key in reviews.keys() - used_reviews:
        print('FAIL: stale secret review (remove or re-review): ' + str(key))
        counts['reviews']+=1
    if reviews: print(f'Secret reviews: {len(used_reviews)} explicitly unconfirmed; new/changed/stale findings fail')
    print(f'Runtime audit: {files} Lua files; '+', '.join(f'{k}={v}' for k,v in sorted(counts.items()))+f'; build={BUILD}')
    if a.check in ('glyphs','all') and not fonts: print('Glyph mode is a symbol-risk policy scan; exact locale font coverage is unverified without --font.')
    return int(any(counts.values()))

if __name__=='__main__':
    sys.exit(main())
