#!/usr/bin/env python3
"""Offline client font/cmap audit. No network, game, WTF access or addon execution.

Uses the existing read-only LocalCASC reader for verified content decoding.
This file adds all-locale root/name lookup; it never changes that reader.
Extracted Blizzard assets stay in the ignored tools/.cache directory.
"""
import argparse
from array import array
from bisect import bisect_left
from collections import Counter
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import re
import struct
import sys
import unicodedata
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
from verify_legs_casc import LocalCASC, EvidenceUnavailable, require

ROOT = Path(__file__).resolve().parent.parent
MASKS = {'enUS': 2, 'koKR': 4, 'frFR': 16, 'deDE': 32, 'zhCN': 64,
         'esES': 128, 'zhTW': 256, 'enGB': 512, 'esMX': 4096,
         'ruRU': 8192, 'ptBR': 16384, 'itIT': 32768, 'ptPT': 65536}
ALPHABETS = {'koKR': 'korean', 'zhCN': 'simplifiedchinese',
             'zhTW': 'traditionalchinese', 'ruRU': 'russian'}
FONT_ADDON = 'Interface/AddOns/Blizzard_Fonts_Shared/'
XML_ORDER = ('Mainline/Fonts.xml', 'Shared/Fonts.xml', 'Shared/GlueFonts.xml',
             'Shared/GameFonts.xml', 'Mainline/GameFonts.xml', 'Shared/FontStyles.xml',
             'Mainline/FontStyles.xml', 'Mainline/GameFontStyles.xml', 'Shared/GameFontStyles.xml')


def store_asset(directory, raw, suffix):
    """Content-addressed, create-only cache; existing content is verified."""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (hashlib.sha256(raw).hexdigest() + suffix)
    try:
        with path.open('xb') as stream: stream.write(raw)
    except FileExistsError:
        require(path.read_bytes() == raw, f'cache digest collision: {path}')
    return str(path)


def path_hash(path):
    """CASC normalized-name Jenkins hashlittle2 (c high, b low)."""
    data = path.replace('/', '\\').upper().encode('utf-8')
    mask = 0xffffffff
    def rot(x, n): return ((x << n) | (x >> (32 - n))) & mask
    a = b = c = (0xdeadbeef + len(data)) & mask
    pos = 0
    while len(data) - pos > 12:
        x, y, z = struct.unpack_from('<III', data, pos)
        a = (a + x) & mask; b = (b + y) & mask; c = (c + z) & mask
        a = ((a - c) & mask) ^ rot(c, 4); c = (c + b) & mask
        b = ((b - a) & mask) ^ rot(a, 6); a = (a + c) & mask
        c = ((c - b) & mask) ^ rot(b, 8); b = (b + a) & mask
        a = ((a - c) & mask) ^ rot(c, 16); c = (c + b) & mask
        b = ((b - a) & mask) ^ rot(a, 19); a = (a + c) & mask
        c = ((c - b) & mask) ^ rot(b, 4); b = (b + a) & mask
        pos += 12
    tail = data[pos:]
    if tail:
        a = (a + int.from_bytes(tail[:4], 'little')) & mask
        b = (b + int.from_bytes(tail[4:8], 'little')) & mask
        c = (c + int.from_bytes(tail[8:12], 'little')) & mask
        c = (c ^ b) - rot(b, 14) & mask
        a = (a ^ c) - rot(c, 11) & mask
        b = (b ^ a) - rot(a, 25) & mask
        c = (c ^ b) - rot(b, 16) & mask
        a = (a ^ c) - rot(c, 4) & mask
        b = (b ^ a) - rot(a, 14) & mask
        c = (c ^ b) - rot(b, 24) & mask
    return (c << 32) | b


class LocaleCASC:
    def __init__(self, install):
        self.reader = LocalCASC(install)
        self.groups = []
        raw = self.reader.root
        pos = struct.unpack_from('<I', raw, 4)[0]
        while pos < len(raw):
            n, locale, f1, f2, f3 = struct.unpack_from('<IIIIB', raw, pos)
            flags = f1 | f2 | (f3 << 17)
            pos += 17
            ids = array('I'); ids.frombytes(raw[pos:pos + n * 4])
            if sys.byteorder != 'little': ids.byteswap()
            current = 0
            for i, delta in enumerate(ids):
                current += delta; ids[i] = current; current += 1
            pos += n * 4
            keys = pos; pos += n * 16
            hashes = None
            if not flags & 0x10000000:
                hashes = array('Q'); hashes.frombytes(raw[pos:pos + n * 8])
                if sys.byteorder != 'little': hashes.byteswap()
                pos += n * 8
            if not flags & 0x100:
                self.groups.append((ids, keys, locale, flags, hashes))
        require(pos == len(raw), 'root bounds mismatch')
        self.names = {}
        self.content = {}

    def resolve(self, path):
        h = path_hash(path)
        if h not in self.names:
            found = set()
            for ids, _, _, _, hashes in self.groups:
                if hashes is not None:
                    found.update(ids[i] for i, v in enumerate(hashes) if v == h)
            require(len(found) == 1, f'path absent/ambiguous in root: {path} ({len(found)})')
            self.names[h] = found.pop()
        return self.names[h]

    def read(self, path, locale='enUS'):
        fid = self.resolve(path) if isinstance(path, str) else path
        groups = sorted(self.groups, key=lambda g: (g[2] == 0, g[3]))
        errors = []
        candidates = []
        for ids, keys, loc, flags, _ in groups:
            if loc and not loc & MASKS[locale]: continue
            i = bisect_left(ids, fid)
            if i < len(ids) and ids[i] == fid:
                key = self.reader.root[keys + i * 16:keys + i * 16 + 16]
                candidates.append((key, loc, flags))
        # Never silently use a neutral variant when a locale-specific variant
        # exists but is unavailable locally.
        specific = [x for x in candidates if x[1]]
        if specific: candidates = specific
        for key, loc, flags in candidates:
            try:
                if key not in self.content: self.content[key] = self.reader.ckey(key)
                raw = self.content[key]
                return raw, dict(fdid=fid, path=path, locale=locale, locale_mask=loc,
                                 flags=flags, ckey=key.hex(), bytes=len(raw),
                                 sha256=hashlib.sha256(raw).hexdigest())
            except EvidenceUnavailable as exc:
                errors.append(str(exc))
        raise EvidenceUnavailable('; '.join(errors) or f'no root variant: {path} {locale}')


def sfnt_tables(raw):
    require(raw[:4] in (b'\0\1\0\0', b'OTTO', b'true'), 'not a standalone SFNT font')
    count = struct.unpack_from('>H', raw, 4)[0]
    require(12 + count * 16 <= len(raw), 'truncated SFNT directory')
    result = {}
    for i in range(count):
        tag, checksum, pos, size = struct.unpack_from('>4sIII', raw, 12 + 16 * i)
        require(pos + size <= len(raw), 'SFNT table outside file')
        result[tag.decode('ascii')] = raw[pos:pos + size]
    return result


def font_names(raw):
    table = sfnt_tables(raw).get('name', b'')
    if not table: return []
    _, count, start = struct.unpack_from('>HHH', table)
    result = set()
    for i in range(count):
        plat, enc, lang, nid, size, pos = struct.unpack_from('>HHHHHH', table, 6 + 12 * i)
        if nid in (1, 2, 4, 6) and lang in (0, 1033):
            result.add(table[start + pos:start + pos + size].decode(
                'utf-16-be' if plat in (0, 3) else 'mac_roman'))
    return sorted(result)


def font_cmap(raw):
    """All Unicode base cmaps; exclude glyph 0, with bounded format 4/12 parsing.

    Formats 0/6/10/13 are supported too. Format 14 contains variation-selector
    mappings, not independent base glyphs; recorded separately.
    """
    table = sfnt_tables(raw).get('cmap')
    require(table is not None and len(table) >= 4, 'missing/truncated cmap')
    result, formats, variations = set(), set(), set()
    num = struct.unpack_from('>H', table, 2)[0]
    require(4 + 8 * num <= len(table), 'truncated cmap directory')
    for i in range(num):
        plat, enc, pos = struct.unpack_from('>HHI', table, 4 + 8 * i)
        if plat != 0 and not (plat == 3 and enc in (1, 10)): continue
        fmt = struct.unpack_from('>H', table, pos)[0]
        length = struct.unpack_from('>I' if fmt in (10, 12, 13) else '>H', table,
                                    pos + (4 if fmt in (10, 12, 13) else 2))[0]
        if fmt == 14: length = struct.unpack_from('>I', table, pos + 2)[0]
        require(pos + length <= len(table), 'cmap subtable outside table')
        sub = table[pos:pos + length]
        formats.add(fmt)
        if fmt == 4:
            seg = struct.unpack_from('>H', sub, 6)[0] // 2
            end = 14; start = end + 2 * seg + 2; delta = start + 2 * seg; ro = delta + 2 * seg
            require(ro + 2 * seg <= len(sub), 'truncated format 4 arrays')
            for j in range(seg):
                hi = struct.unpack_from('>H', sub, end + 2 * j)[0]
                lo = struct.unpack_from('>H', sub, start + 2 * j)[0]
                d = struct.unpack_from('>h', sub, delta + 2 * j)[0]
                r = struct.unpack_from('>H', sub, ro + 2 * j)[0]
                require(lo <= hi, 'invalid format 4 range')
                for cp in range(lo, hi + 1):
                    if cp == 65535: continue
                    if r:
                        at = ro + 2 * j + r + 2 * (cp - lo)
                        require(at + 2 <= len(sub), 'format 4 glyph offset outside subtable')
                        gid = struct.unpack_from('>H', sub, at)[0]
                        gid = ((gid + d) & 65535) if gid else 0
                    else: gid = (cp + d) & 65535
                    if gid: result.add(cp)
        elif fmt in (12, 13):
            count = struct.unpack_from('>I', sub, 12)[0]
            require(16 + count * 12 <= len(sub), 'truncated format 12/13 groups')
            for j in range(count):
                lo, hi, glyph = struct.unpack_from('>III', sub, 16 + 12 * j)
                require(lo <= hi <= 0x10ffff, 'invalid Unicode cmap range')
                if fmt == 12: result.update(range(lo + (glyph == 0), hi + 1))
                elif glyph: result.update(range(lo, hi + 1))
        elif fmt in (6, 10):
            at = 6 if fmt == 6 else 12
            lo, count = struct.unpack_from('>HH' if fmt == 6 else '>II', sub, at)
            at += 4 if fmt == 6 else 8
            require(at + count * 2 <= len(sub) and lo + count <= 0x110000, 'bad trimmed cmap')
            result.update(lo + j for j in range(count) if struct.unpack_from('>H', sub, at + 2 * j)[0])
        elif fmt == 0:
            require(len(sub) >= 262, 'truncated format 0 cmap')
            result.update(cp for cp, glyph in enumerate(sub[6:262]) if glyph)
        elif fmt == 14:
            variations.add(fmt)
        else:
            raise EvidenceUnavailable(f'unsupported Unicode cmap format {fmt}')
    require(result, 'empty Unicode cmap')
    return result, sorted(formats), sorted(variations)


TOKEN = re.compile(r'[A-Za-z_][A-Za-z_0-9]*|\d+(?:\.\d+)?|\.\.\.|\.\.|==|~=|<=|>=|.', re.S)
LONG = re.compile(r'\[(=*)\[')


def decode_lua(raw):
    out = bytearray(); pos = 0
    escapes = {'a': 7, 'b': 8, 'f': 12, 'n': 10, 'r': 13, 't': 9, 'v': 11}
    while pos < len(raw):
        if raw[pos] != '\\':
            out.extend(raw[pos].encode('utf-8')); pos += 1; continue
        pos += 1
        require(pos < len(raw), 'trailing Lua escape')
        match = re.match(r'[0-9]{1,3}', raw[pos:])
        if match:
            n = int(match[0]); require(n <= 255, 'invalid Lua byte escape')
            out.append(n); pos += len(match[0])
        else:
            ch = raw[pos]; pos += 1
            if ch in '\r\n':
                if ch == '\r' and pos < len(raw) and raw[pos] == '\n': pos += 1
                out.append(10)
            else: out.extend(bytes([escapes[ch]]) if ch in escapes else ch.encode('utf-8'))
    return out.decode('utf-8', 'surrogateescape')


def lua_tokens(text):
    """Lex, without executing Lua, preserving every non-comment literal."""
    result = []; pos = 0; line = 1
    while pos < len(text):
        begin = pos; start_line = line
        if text[pos].isspace():
            line += text[pos] == '\n'; pos += 1; continue
        comment = text.startswith('--', pos)
        if comment: pos += 2
        long = LONG.match(text, pos)
        if long:
            endmark = ']' + long[1] + ']'
            start = long.end(); end = text.find(endmark, start)
            require(end >= 0, f'unclosed Lua long string/comment at {line}')
            value = text[start:end].replace('\r\n', '\n').replace('\r', '\n')
            if value.startswith('\n'): value = value[1:]
            pos = end + len(endmark)
            if not comment: result.append(('string', value, start_line))
        elif comment:
            end = text.find('\n', pos); pos = len(text) if end < 0 else end
        elif text[pos] in ('"', "'"):
            quote = text[pos]; pos += 1; start = pos
            while pos < len(text):
                if text[pos] == '\\': pos += 2
                elif text[pos] == quote: break
                else: pos += 1
            require(pos < len(text), f'unclosed Lua string at {line}')
            result.append(('string', decode_lua(text[start:pos]), start_line)); pos += 1
        else:
            match = TOKEN.match(text, pos)
            result.append(('code', match[0], start_line)); pos = match.end()
        line += text[begin:pos].count('\n')
    # Constant concatenation may split UTF-8 byte sequences between literals.
    merged = []; i = 0
    while i < len(result):
        kind, value, line = result[i]; i += 1
        if kind == 'string':
            raw = value.encode('utf-8', 'surrogateescape')
            while i + 1 < len(result) and result[i][:2] == ('code', '..') and result[i + 1][0] == 'string':
                raw += result[i + 1][1].encode('utf-8', 'surrogateescape'); i += 2
            value = raw.decode('utf-8', 'surrogateescape')
        merged.append((kind, value, line))
    return merged


def visible_text(value):
    """Remove rendered markup payloads, keeping hyperlink labels and ||."""
    # Protect literal pipes before interpreting control sequences.
    value = value.replace('||', '\x00')
    value = re.sub(r'\|[TA].*?\|[ta]', '', value, flags=re.S)
    value = re.sub(r'\|H.*?\|h', '', value, flags=re.S)
    value = re.sub(r'\|K.*?\|k', '', value, flags=re.S)
    value = re.sub(r'\|c[0-9a-fA-F]{8}|\|cn[A-Za-z_0-9]+:', '', value)
    value = re.sub(r'\|[rh]|\|n', '', value)
    # Format directives produce dynamic values, not the directive's letters.
    value = re.sub(r'%%', '\x01', value)
    value = re.sub(r'%[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGqs]', '', value)
    return value.replace('\x00', '|').replace('\x01', '%')


def collect_strings(root, cache):
    records, inputs, unresolved, skipped = [], [], [], []
    locale_values = {}
    locale_records = {}
    files = sorted(p for folder in ('WaypointTracker', 'WaypointTracker_Data')
                   for p in (root / folder).rglob('*') if p.suffix in ('.lua', '.xml', '.toc'))
    for path in files:
        raw = path.read_bytes(); rel = str(path.relative_to(root))
        evidence = dict(file=rel, sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw))
        evidence['snapshot'] = store_asset(cache / 'sources', raw, path.suffix)
        inputs.append(evidence)
        text = raw.decode('utf-8-sig')
        if path.suffix == '.lua':
            tokens = lua_tokens(text)
            loc = path.stem if path.parent.name == 'Locales' else None
            if loc and loc not in MASKS:
                unresolved.append(dict(file=rel, locale=loc, reason='locale has no known CASC mask/font alphabet'))
            suffix = re.search(r'_([a-z]{2}[A-Z]{2})$', path.stem)
            locales = [suffix[1]] if suffix and suffix[1] in MASKS else list(MASKS)
            assigned = {}
            for i, (kind, value, line) in enumerate(tokens):
                if kind != 'code' or value != 'L': continue
                key, end = None, i + 1
                if i + 2 < len(tokens) and tokens[i + 1][1] == '.':
                    key = tokens[i + 2][1]; end = i + 3
                elif i + 3 < len(tokens) and tokens[i + 1][1] == '[' and tokens[i + 2][0] == 'string' and tokens[i + 3][1] == ']':
                    key = tokens[i + 2][1]; end = i + 4
                if key and end < len(tokens) and tokens[end][1] == '=':
                    if end + 1 < len(tokens) and tokens[end + 1][0] == 'string':
                        assigned[end + 1] = key
                        if loc and end + 2 < len(tokens) and tokens[end + 2][1] == '..':
                            unresolved.append(dict(file=rel, key=key, line=line, reason='dynamic locale concatenation'))
                    elif loc:
                        unresolved.append(dict(file=rel, key=key, line=line, reason='nonliteral locale assignment'))
            values, loc_records = {}, []
            scopes = []
            for i, (kind, value, line) in enumerate(tokens):
                if kind == 'code' and value == '{':
                    label = tokens[i - 2][1] if i >= 2 and tokens[i - 1][1] == '=' else ''
                    scopes.append(label)
                elif kind == 'code' and value == '}' and scopes:
                    scopes.pop()
                if kind != 'string': continue
                key = assigned.get(i, f'@literal:{line}:{i}')
                if any(0xdc80 <= ord(ch) <= 0xdcff for ch in value) or any(ord(ch) < 32 and ch not in '\n\r\t' for ch in value):
                    skipped.append(dict(file=rel, key=key, line=line, reason='binary/control Lua literal (not a renderable UTF-8 string)'))
                    if loc and i in assigned:
                        unresolved.append(dict(file=rel, key=key, line=line, reason='binary locale value'))
                    continue
                scoped_locales = [s for s in scopes if s in MASKS]
                selected_locales = [scoped_locales[-1]] if scoped_locales else locales
                # Generic English data is also used for unbundled locale aliases.
                if selected_locales == ['enUS']: selected_locales = ['enUS', 'enGB', 'itIT', 'ptPT']
                if selected_locales == ['esES']: selected_locales = ['esES', 'esMX']
                record = dict(file=rel, key=key, line=line, text=value, kind='locale' if loc else 'literal', locales=selected_locales)
                if loc:
                    if i in assigned:
                        values[key] = record; loc_records.append(record)
                else:
                    # Search/normalization patterns are not UI output. Retain a
                    # precise exclusion rather than reporting their alphabets as
                    # though the addon displayed them in every locale.
                    is_pattern = i >= 2 and tokens[i - 1][1] == '(' and tokens[i - 2][1] in ('gsub', 'gmatch', 'match', 'find')
                    # Geo.Lower's replacement is another non-display case;
                    # leave other replacement literals in the conservative scan.
                    is_geo_case = rel == 'WaypointTracker/Geo.lua' and value == 'ё' and i >= 3 and tokens[i - 1][1] == ',' and tokens[i - 2][1] == 'Ё'
                    if is_pattern or is_geo_case:
                        skipped.append(dict(file=rel, key=key, line=line, reason='Lua search/case-normalization literal, not UI output'))
                    elif re.match(r'\d+\t', value):
                        label = tokens[i - 2][1] if i >= 2 and tokens[i - 1][1] == '=' else key
                        for row, content in enumerate(value.splitlines(), 1):
                            fields = content.split('\t', 1)
                            if len(fields) == 2:
                                records.append(dict(record, key=f'{label}[{fields[0]}]', line=line + row,
                                                    text=fields[1], kind='packed-data'))
                    else: records.append(record)
            if loc:
                locale_values[loc] = values; locale_records[loc] = loc_records
        elif path.suffix == '.toc':
            for line, value in enumerate(text.splitlines(), 1):
                match = re.match(r'##\s*(Title|Notes|Category)(?:-([a-z]{2}[A-Z]{2}))?:\s*(.*)', value)
                if match:
                    key, locale, content = match.groups()
                    records.append(dict(file=rel, key=key + ('-' + locale if locale else ''), line=line,
                                        text=content, kind='metadata', locales=[locale] if locale else list(MASKS)))
        else:
            tree = ET.fromstring(raw)
            for i, element in enumerate(tree.iter()):
                if element.tag.rsplit('}', 1)[-1] in ('Script', 'OnLoad', 'OnClick') and element.text:
                    for j, (kind, value, line) in enumerate(lua_tokens(element.text)):
                        if kind == 'string':
                            records.append(dict(file=rel, key=f'@xmlscript:{i}:{j}', line=line, text=value,
                                                kind='xml-script-literal', locales=list(MASKS)))
                if element.get('text'):
                    records.append(dict(file=rel, key=element.get('name', f'@xml:{i}') + ':text', line=1,
                                        text=element.get('text'), kind='xml-text', locales=list(MASKS)))
    english = locale_values.get('enUS', {})
    require(english, 'no English locale assignments extracted')
    for locale in MASKS:
        name = 'esES' if locale == 'esMX' else locale
        chosen = locale_values.get(name, {})
        # Audit every assigned value, including overwritten/extra keys.
        for rec in locale_records.get(name, locale_records['enUS']):
            records.append(dict(rec, locales=[locale]))
        if name in locale_values and name != 'enUS':
            records.extend(dict(rec, locales=[locale], kind='english-fallback')
                           for key, rec in english.items() if key not in chosen)
    for path in inputs:
        live = root / path['file']
        if hashlib.sha256(live.read_bytes()).hexdigest() != path['sha256']:
            unresolved.append(dict(file=path['file'], reason='source changed during collection; snapshot was audited'))
    return records, inputs, unresolved, skipped


def load_fonts(casc, cache):
    definitions, evidence, unresolved = {}, [], []
    toc, item = casc.read(FONT_ADDON + 'Blizzard_Fonts_Shared.toc')
    item['extracted'] = store_asset(cache / 'assets', toc, '.toc'); evidence.append(item)
    for name in XML_ORDER:
        raw, item = casc.read(FONT_ADDON + name)
        item['extracted'] = store_asset(cache / 'assets', raw, '.xml'); evidence.append(item)
        for element in ET.fromstring(raw):
            tag = element.tag.rsplit('}', 1)[-1]
            if tag == 'FontFamily':
                definitions[element.get('name')] = dict(members={m.get('alphabet'): next(
                    f.get('font').replace('\\', '/') for f in m if f.tag.endswith('Font')) for m in element}, source=item['path'])
            elif tag == 'Font' and element.get('name'):
                definitions[element.get('name')] = dict(inherits=element.get('inherits'),
                                                        font=element.get('font'), source=item['path'])
    all_paths = set()
    for definition in definitions.values():
        all_paths.update(definition.get('members', {}).values())
        if definition.get('font'): all_paths.add(definition['font'].replace('\\', '/'))
    # Damage/name alternatives can appear in Script constants, not FontFamily.
    for item in evidence:
        if item['path'].endswith('.xml'):
            text = Path(item['extracted']).read_text()
            all_paths.update(p.replace('\\\\', '/').replace('\\', '/') for p in re.findall(r'Fonts[\\/]+[A-Za-z_0-9]+\.[tT][tT][fF]', text))
    fonts = {}; cmaps = {}; cmap_metadata = {}
    for path in sorted({p.upper() for p in all_paths}):
        for locale in MASKS:
            try:
                raw, item = casc.read(path, locale)
                if item['sha256'] not in cmaps:
                    cmap, formats, variations = font_cmap(raw)
                    cmaps[item['sha256']] = cmap
                    cmap_metadata[item['sha256']] = (formats, variations)
                else:
                    formats, variations = cmap_metadata[item['sha256']]
                item.update(names=font_names(raw), codepoints=len(cmaps[item['sha256']]), formats=formats,
                            variations=variations, extracted=store_asset(cache / 'assets', raw, '.ttf'))
                fonts[(path, locale)] = item
            except (EvidenceUnavailable, ValueError, struct.error) as exc:
                unresolved.append(dict(path=path, locale=locale, reason=str(exc)))
    return definitions, evidence, fonts, cmaps, unresolved


def resolve_family(name, definitions, seen=()):
    require(name not in seen, 'font inheritance cycle')
    require(name in definitions, f'font definition missing: {name}')
    item = definitions[name]
    if 'members' in item: return {k: v.upper() for k, v in item['members'].items()}
    if item.get('font'): return {'roman': item['font'].replace('\\', '/').upper()}
    return resolve_family(item['inherits'], definitions, (*seen, name))


def audit(root, install, cache):
    records, inputs, unresolved, skipped = collect_strings(root, cache)
    casc = LocaleCASC(install)
    definitions, xml, fonts, cmaps, failures = load_fonts(casc, cache)
    unresolved += failures
    used_objects = {'GameFontNormal', 'GameFontHighlight', 'GameFontHighlightSmall', 'ChatFontNormal', 'NumberFontNormalSmall'}
    for item in inputs:
        text = Path(item['snapshot']).read_text()
        used_objects.update(re.findall(r'\b(?:GameFont|ChatFont|NumberFont)[A-Za-z_0-9]*', text))
    families = {}
    for name in sorted(used_objects):
        try: families[name] = resolve_family(name, definitions)
        except EvidenceUnavailable as exc: unresolved.append(dict(font_object=name, reason=str(exc)))
    # Locale/UI text is conservatively checked against every text family used
    # by this addon. Numeric pin fonts only need digits, not every translation.
    text_objects = [n for n in families if not n.startswith('NumberFont')]
    holes, family_holes, stats = [], [], {}
    for locale in MASKS:
        alphabet = ALPHABETS.get(locale, 'roman')
        active = {}
        for name in text_objects:
            members = families[name]; selected = members.get(alphabet, members.get('roman'))
            if not selected: continue
            item = fonts.get((selected, locale))
            if item: active.setdefault(selected, []).append(name)
        family_unions = {}
        for name in text_objects:
            union = set()
            for path in families[name].values():
                item = fonts.get((path, locale))
                if item: union.update(cmaps[item['sha256']])
            family_unions[name] = union
        selected_records = [rec for rec in records if locale in rec['locales']]
        chars = set()
        for rec in selected_records:
            needed = {ord(ch) for ch in visible_text(rec['text']) if ch not in '\n\r\t'}
            chars.update(needed)
            for path, objects in active.items():
                cmap = cmaps[fonts[(path, locale)]['sha256']]
                for cp in sorted(needed - cmap):
                    family_available = all(cp in family_unions[name] for name in objects)
                    finding = dict(locale=locale, file=rec['file'], key=rec['key'], line=rec['line'],
                                      kind=rec['kind'], codepoint=f'U+{cp:04X}', character=chr(cp),
                                      unicode_name=unicodedata.name(chr(cp), 'UNNAMED'), font=path,
                                      font_objects=objects, family_member_covered=family_available,
                                      alternative_fonts=sorted({p for name in objects for p in families[name].values()
                                          if (p, locale) in fonts and cp in cmaps[fonts[(p, locale)]['sha256']]}))
                    holes.append(finding)
                    if not family_available: family_holes.append(finding)
        stats[locale] = dict(strings=len(selected_records), unique_codepoints=len(chars),
                             primary_fonts=sorted(active), locale_assignments=sum(r['kind'] == 'locale' for r in selected_records),
                             primary_missing=sum(h['locale'] == locale for h in holes),
                             family_missing=sum(h['locale'] == locale for h in family_holes))
    for item in inputs:
        if hashlib.sha256((root / item['file']).read_bytes()).hexdigest() != item['sha256']:
            unresolved.append(dict(file=item['file'], reason='source changed during audit; snapshot was audited'))
    numeric = {}
    for locale in MASKS:
        paths = families['NumberFontNormalSmall']
        path = paths.get(ALPHABETS.get(locale, 'roman'), paths['roman'])
        font = fonts.get((path, locale))
        missing = sorted(set(map(ord, '0123456789')) - cmaps[font['sha256']]) if font else list(map(ord, '0123456789'))
        numeric[locale] = dict(font=path, missing=[f'U+{cp:04X}' for cp in missing])
        if missing: unresolved.append(dict(locale=locale, font=path, reason='numeric font has unavailable/missing digits'))
    return dict(timestamp=datetime.now(timezone.utc).isoformat(), build=casc.reader.build,
                build_key=casc.reader.build_key, build_config=casc.reader.config['build-name'][0],
                inputs=inputs, xml=xml, fonts=list(fonts.values()), families=families, stats=stats, numeric=numeric,
                primary_missing=holes, family_missing=family_holes, unresolved=unresolved, skipped=skipped,
                limitations=['Native fallback order/character-to-alphabet routing is not executed or proven by XML.',
                             'Mainline definitions are present in this build; native [Family] resolution is not executed.',
                             'Literal scanning is a conservative superset of UI sinks, not a dynamic dataflow proof.',
                             'Imported names, saved user text, client API values and formatted dynamic arguments are outside static coverage.',
                             'NumberFontNormalSmall is checked separately for ASCII digits only.'])


def probe(casc):
    paths = ['Fonts/' + name for name in ('FRIZQT__.TTF', 'ARIALN.TTF', 'MORPHEUS.TTF',
             'SKURRI.TTF', 'FRIZQT___CYR.TTF', 'ARIALN_CYR.TTF', 'MORPHEUS_CYR.TTF',
             'SKURRI_CYR.TTF', '2002.TTF', '2002B.TTF', 'K_Pagetext.TTF', 'ARKai_T.TTF',
             'ARKai_C.TTF', 'ARHei.TTF', 'bLEI00D.TTF', 'bKAI00M.TTF', 'bHEI00M.TTF',
             'bHEI01B.TTF', 'ZYKai_T.TTF', 'ZYKai_C.TTF', 'ZYHei.TTF')]
    paths += ['Interface/' + directory + '/' + name for directory in
              ('FrameXML', 'SharedXML', 'AddOns/Blizzard_SharedXML', 'AddOns/Blizzard_SharedXMLBase')
              for name in ('Fonts.xml', 'Fonts.lua', 'FontStyles.xml', 'FontStyles.lua', 'FontUtil.lua')]
    for path in paths:
        try:
            raw, evidence = casc.read(path)
            print(json.dumps(evidence, ensure_ascii=False))
            if raw[:4] in (b'\0\1\0\0', b'OTTO'):
                cmap, formats, _ = font_cmap(raw)
                print(font_names(raw), 'cmap', len(cmap), formats)
            else: print(raw.decode('utf-8')[:18000])
        except (EvidenceUnavailable, ValueError, struct.error) as exc:
            print(path, 'UNRESOLVED', str(exc))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', type=Path, default=Path('/Applications/World of Warcraft'))
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--cache', type=Path, default=ROOT / 'tools/.cache/font-coverage')
    parser.add_argument('--json', type=Path, help='create-only evidence JSON path')
    parser.add_argument('--probe', action='store_true', help='list local font/UI path evidence')
    parser.add_argument('--strict', action='store_true', help='fail also for unresolved native fallback/font mapping')
    parser.add_argument('--details', action='store_true', help='print every missing character (JSON always contains all)')
    args = parser.parse_args()
    if args.probe:
        probe(LocaleCASC(args.install)); return 0
    result = audit(args.root, args.install, args.cache)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        with args.json.open('x') as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2); stream.write('\n')
    print('CLIENT', result['build']['Version!STRING:0'], result['build']['Product!STRING:0'], result['build_key'])
    print('INPUTS', len(result['inputs']), 'FONT VARIANTS', len(result['fonts']),
          'UNIQUE FONT FILES', len({f['sha256'] for f in result['fonts']}))
    for locale, stats in result['stats'].items(): print(locale, json.dumps(stats))
    for finding in result['primary_missing'] if args.details else result['primary_missing'][:40]:
        print('CMAP_MISSING', finding['locale'], f"{finding['file']}:{finding['key']}:{finding['line']}",
              finding['codepoint'], repr(finding['character']), finding['font'],
              'FAMILY_MEMBER_AVAILABLE' if finding['family_member_covered'] else 'FAMILY_CMAP_MISSING')
    if len(result['primary_missing']) > 40 and not args.details:
        print('Further occurrences in JSON; use --details for all:', len(result['primary_missing']) - 40)
    for issue in result['unresolved']: print('UNRESOLVED', json.dumps(issue, ensure_ascii=False))
    print('Native fallback routing: UNRESOLVED (offline cmap presence is not a rendering test).')
    if result['primary_missing']: return 1
    if result['unresolved'] or args.strict: return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
