#!/usr/bin/env python3
"""Offline font audit regression entry; no game/client writes or network.

    python3 -B tests/check_font_coverage.py
    python3 -B tests/check_font_coverage.py --evidence docs/font-coverage-v4.json

With --evidence, validate the real extracted font cmaps too. If fontTools is
already installed in the interpreter, independently compare every Unicode cmap;
it is optional and is never downloaded or installed by this test.
"""
import argparse
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import validate_font_coverage as audit


def sfnt(subtable, encoding=1):
    cmap = struct.pack('>HHHHI', 0, 1, 3, encoding, 12) + subtable
    return struct.pack('>4sHHHH', b'\0\1\0\0', 1, 16, 0, 0) + struct.pack('>4sIII', b'cmap', 0, 28, len(cmap)) + cmap


def cmap4(lo, hi, delta, glyphs=None):
    length = 32 + (2 * len(glyphs) if glyphs is not None else 0)
    header = struct.pack('>HHHHHHH', 4, length, 0, 4, 4, 1, 0)
    arrays = struct.pack('>HHHHHhhHH', hi, 65535, 0, lo, 65535, delta, 1,
                         4 if glyphs is not None else 0, 0)
    return header + arrays + (struct.pack('>' + 'H' * len(glyphs), *glyphs) if glyphs is not None else b'')


class CmapTests(unittest.TestCase):
    def test_direct_delta_does_not_confuse_codepoint_zero_with_glyph_zero(self):
        self.assertEqual(audit.font_cmap(sfnt(cmap4(0, 1, 1)))[0], {0, 1})

    def test_direct_delta_zero_is_missing(self):
        self.assertEqual(audit.font_cmap(sfnt(cmap4(65, 66, -65)))[0], {66})

    def test_indirect_zero_and_delta_wrap(self):
        self.assertEqual(audit.font_cmap(sfnt(cmap4(65, 67, 2, [0, 3, 65535])))[0], {66, 67})

    def test_indirect_delta_can_produce_missing(self):
        self.assertEqual(audit.font_cmap(sfnt(cmap4(65, 66, -1, [1, 2])))[0], {66})

    def test_astral_format12_excludes_initial_glyph_zero(self):
        sub = struct.pack('>HHIII', 12, 0, 28, 0, 1) + struct.pack('>III', 0x1f600, 0x1f601, 0)
        self.assertEqual(audit.font_cmap(sfnt(sub, 10))[0], {0x1f601})

    def test_format13_constant_nonzero_glyph(self):
        sub = struct.pack('>HHIII', 13, 0, 28, 0, 1) + struct.pack('>III', 65, 67, 1)
        self.assertEqual(audit.font_cmap(sfnt(sub, 10))[0], {65, 66, 67})

    def test_truncated_font_fails_instead_of_passing(self):
        with self.assertRaises((ValueError, struct.error)):
            audit.font_cmap(sfnt(cmap4(65, 66, 0))[:-1])

    def test_unsupported_font_fails(self):
        with self.assertRaises(ValueError): audit.font_cmap(b'guls' + bytes(40))


class StringTests(unittest.TestCase):
    def test_comments_long_strings_and_decimal_utf8(self):
        ts = audit.lua_tokens('-- ▲\n--[=[✓]=]\nL.X="\\226\\150\\178"\nL.Y=[=[\n中文]=]')
        self.assertEqual([x[1] for x in ts if x[0] == 'string'], ['▲', '中文'])

    def test_utf8_split_by_constant_concatenation(self):
        ts = audit.lua_tokens('L.X = "\\226" .. "\\150\\178"')
        self.assertEqual([x[1] for x in ts if x[0] == 'string'], ['▲'])

    def test_markup_keeps_only_rendered_hyperlink_text_and_literal_pipes(self):
        s = '|cffff0000é|r |Hitem:999:★|h[中文]|h |Ttexture:✓:16|t |A:atlas:▲|a || %% %02d %.1f %s'
        self.assertEqual(audit.visible_text(s), 'é [中文]   | %   ')

    def test_ascii_name_hash_is_case_and_separator_insensitive(self):
        self.assertEqual(audit.path_hash('Fonts/FRIZQT__.TTF'), audit.path_hash('fonts\\frizqt__.ttf'))

    def test_scopes_packed_rows_and_english_fallback(self):
        # Temporary artifacts remain under the allowed, ignored cache tree.
        parent = ROOT / 'tools/.cache/font-coverage/tests'; parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as temp:
            root = Path(temp); locales = root / 'WaypointTracker/Locales'; locales.mkdir(parents=True)
            (locales / 'enUS.lua').write_text('L.X="English"\nL.Y="Fallback"\n')
            (locales / 'esES.lua').write_text('L.X="Español"\n')
            data = root / 'WaypointTracker_Data'; data.mkdir()
            (data / 'Client.lua').write_text('D.client={ruRU={towns=[[\n1\tРусский\n]]},zhTW={towns=[[\n2\t中文\n]]}}')
            records, inputs, issues, skipped = audit.collect_strings(root, root / 'cache')
            self.assertFalse(issues)
            self.assertEqual(next(r['locales'] for r in records if r['key'] == 'towns[1]'), ['ruRU'])
            self.assertEqual(next(r['locales'] for r in records if r['key'] == 'towns[2]'), ['zhTW'])
            self.assertEqual(next(r['text'] for r in records if r['key'] == 'X' and r['locales'] == ['esMX']), 'Español')
            self.assertTrue(any(r['key'] == 'Y' and r['kind'] == 'english-fallback' and r['locales'] == ['esMX'] for r in records))

    def test_dynamic_locale_expression_is_unresolved(self):
        parent = ROOT / 'tools/.cache/font-coverage/tests'; parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as temp:
            root = Path(temp); locales = root / 'WaypointTracker/Locales'; locales.mkdir(parents=True)
            (locales / 'enUS.lua').write_text('L.X="English" .. dynamic\nL.Y=helper()')
            _, _, issues, _ = audit.collect_strings(root, root / 'cache')
            self.assertEqual({i['reason'] for i in issues}, {'dynamic locale concatenation', 'nonliteral locale assignment'})


def check_evidence(path):
    result = json.loads(path.read_text())
    unique = {f['sha256']: f for f in result['fonts']}
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        TTFont = None
    for sha, font in unique.items():
        extracted = Path(font['extracted'])
        raw = extracted.read_bytes()
        assert audit.hashlib.sha256(raw).hexdigest() == sha, extracted
        actual, formats, _ = audit.font_cmap(raw)
        assert len(actual) == font['codepoints'] and formats == font['formats'], extracted
        if TTFont:
            other = TTFont(extracted, lazy=True)
            expected = set()
            for table in other['cmap'].tables:
                if table.isUnicode() and hasattr(table, 'cmap'):
                    expected.update(cp for cp, name in table.cmap.items() if other.getGlyphID(name) != 0)
            other.close()
            assert actual == expected, (font['path'], sorted(actual ^ expected))
    lookup = {(f['path'], f['locale']): audit.font_cmap(Path(f['extracted']).read_bytes())[0] for f in result['fonts']}
    # Every reported hole must really be absent, and its alternatives must be
    # members of the associated UI family, not arbitrary installed fonts.
    for finding in result['primary_missing']:
        cp = int(finding['codepoint'][2:], 16)
        assert cp not in lookup[(finding['font'], finding['locale'])]
        for alternative in finding['alternative_fonts']:
            assert any(alternative in result['families'][name].values() for name in finding['font_objects'])
            assert cp in lookup[(alternative, finding['locale'])]
    assert all(not item['missing'] for item in result['numeric'].values())
    assert not result['unresolved'], result['unresolved']
    print(f"Evidence PASS: {len(unique)} verified font files; {len(result['primary_missing'])} verified primary cmap gaps; "
          f"independent FontTools comparison {'PASS' if TTFont else 'not available (optional)'}.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    passed = unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful()
    if passed and args.evidence: check_evidence(args.evidence)
    raise SystemExit(0 if passed else 1)
