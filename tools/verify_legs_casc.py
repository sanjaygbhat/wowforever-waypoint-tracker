#!/usr/bin/env python3
"""Small, offline, read-only CASC reader for local WoW terrain verification.

Supports local v7 indexes, BLTE N/Z, EN v1 and WoW TSFM root v2.
Unsupported/encrypted/missing content raises an error; no network or writes.
Wire layout references (implementations are independent Python):
https://github.com/ladislav-zezula/CascLib/blob/master/src/CascStructs.h
https://github.com/ladislav-zezula/CascLib/blob/master/src/CascRootFile_WoW.cpp
CascLib is MIT; no CascLib source or Blizzard assets are bundled here.
"""
from array import array
from bisect import bisect_left, bisect_right
import csv
import hashlib
from pathlib import Path
import struct
import sys
import zlib


class EvidenceUnavailable(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise EvidenceUnavailable(reason)


def chunks(data, reverse=True):
    """Yield bounded IFF chunks; ADT/WDT IDs use reversed byte order."""
    pos = 0
    while pos < len(data):
        require(pos + 8 <= len(data), "truncated IFF header")
        name = data[pos:pos + 4]
        if reverse:
            name = name[::-1]
        size = struct.unpack_from('<I', data, pos + 4)[0]
        require(pos + 8 + size <= len(data), "truncated IFF payload")
        yield name.decode('ascii'), data[pos + 8:pos + 8 + size]
        pos += 8 + size


def blte(data):
    require(data[:4] == b'BLTE', "not BLTE")
    header_size = int.from_bytes(data[4:8], 'big')

    def frame(payload):
        if payload[:1] == b'N':
            return payload[1:]
        if payload[:1] == b'Z':
            return zlib.decompress(payload[1:])
        raise EvidenceUnavailable("unsupported/encrypted BLTE mode " + repr(payload[:1]))

    if header_size == 0:
        return frame(data[8:])
    require(data[8] == 0x0f, "unsupported BLTE table")
    count = int.from_bytes(data[9:12], 'big')
    require(header_size == 12 + count * 24, "bad BLTE table size")
    result = []
    pos = header_size
    for i in range(count):
        compressed, decompressed = struct.unpack_from('>II', data, 12 + i * 24)
        digest = data[20 + i * 24:36 + i * 24]
        payload = data[pos:pos + compressed]
        require(len(payload) == compressed and hashlib.md5(payload).digest() == digest,
                "BLTE frame checksum mismatch")
        raw = frame(payload)
        require(len(raw) == decompressed, "BLTE frame size mismatch")
        result.append(raw)
        pos += compressed
    require(pos == len(data), "extra/truncated BLTE data")
    return b''.join(result)


class LocalCASC:
    def __init__(self, install):
        self.install = Path(install)
        self.data = self.install / 'Data'
        with (self.install / '.build.info').open() as stream:
            rows = list(csv.DictReader(stream, delimiter='|'))
        self.build = next(r for r in rows if r['Active!DEC:1'] == '1'
                          and r['Product!STRING:0'] == 'wow_classic_beta')
        self.build_key = self.build['Build Key!HEX:16']
        p = self.data / 'config' / self.build_key[:2] / self.build_key[2:4] / self.build_key
        config_bytes = p.read_bytes()
        require(hashlib.md5(config_bytes).hexdigest() == self.build_key, "build config MD5 mismatch")
        self.config = {}
        for line in config_bytes.decode().splitlines():
            if ' = ' in line:
                k, v = line.split(' = ', 1)
                self.config[k] = v.split()
        self.index = {}
        newest = {}
        for p in (self.data / 'data').glob('*.idx'):
            newest[p.name[:2]] = max(newest.get(p.name[:2], p), p)
        for p in sorted(newest.values()):
            raw = p.read_bytes()
            require(raw[:4] == b'\x10\0\0\0' and raw[8:10] == b'\x07\0'
                    and raw[12:16] == bytes([4, 5, 9, 30]), "unsupported local index")
            size = struct.unpack_from('<I', raw, 32)[0]
            require(size % 18 == 0 and 40 + size <= len(raw), "invalid index size")
            for pos in range(40, 40 + size, 18):
                key = raw[pos:pos + 9]
                location = int.from_bytes(raw[pos + 9:pos + 14], 'big')
                length = int.from_bytes(raw[pos + 14:pos + 18], 'little')
                entry = (location >> 30, location & ((1 << 30) - 1), length)
                require(key not in self.index or self.index[key] == entry, "ambiguous local EKey")
                self.index[key] = entry
        self.encoding = self.ekey(bytes.fromhex(self.config['encoding'][1]))
        require(hashlib.md5(self.encoding).hexdigest() == self.config['encoding'][0],
                "encoding content checksum mismatch")
        en = self.encoding
        require(en[:5] == b'EN\x01\x10\x10', "unsupported encoding manifest")
        self.page_size = int.from_bytes(en[5:7], 'big') * 1024
        n = int.from_bytes(en[9:13], 'big')
        self.directory = 22 + int.from_bytes(en[18:22], 'big')
        self.pages = self.directory + n * 32
        self.first_keys = [en[self.directory + i * 32:self.directory + i * 32 + 16]
                           for i in range(n)]
        self.root = self.ckey(bytes.fromhex(self.config['root'][0]))
        require(self.root[:4] == b'TSFM' and struct.unpack_from('<I', self.root, 8)[0] == 2,
                "unsupported WoW root (requires TSFM v2)")
        self.groups = []
        pos = struct.unpack_from('<I', self.root, 4)[0]
        total = 0
        while pos < len(self.root):
            n, locale, f1, f2, f3 = struct.unpack_from('<IIIIB', self.root, pos)
            flags = f1 | f2 | (f3 << 17)
            pos += 17
            ids = array('I')
            ids.frombytes(self.root[pos:pos + 4 * n])
            if sys.byteorder != 'little':
                ids.byteswap()
            current = 0
            for i, delta in enumerate(ids):
                current += delta
                ids[i] = current
                current += 1
            pos += 4 * n
            if (locale == 0 or locale & 2) and not flags & 0x100:
                self.groups.append((ids, pos, locale, flags))
            pos += 16 * n
            if not flags & 0x10000000:
                pos += 8 * n
            total += n
        require(pos == len(self.root) and total == struct.unpack_from('<I', self.root, 12)[0],
                "root group count/bounds mismatch")
        self.groups.sort(key=lambda g: (g[2] != 0, g[3]))
        self.root_entries = total
        self.manifest = {}

    def ekey(self, key):
        try:
            archive, offset, size = self.index[key[:9]]
        except KeyError:
            raise EvidenceUnavailable("content absent from local indexes: " + key.hex()) from None
        with (self.data / 'data' / ('data.%03d' % archive)).open('rb') as stream:
            stream.seek(offset)
            raw = stream.read(size)
        require(len(raw) == size and raw[30:34] == b'BLTE', "invalid archive record")
        return blte(raw[30:])

    def ckey(self, key):
        i = bisect_right(self.first_keys, key) - 1
        require(i >= 0, "CKey outside encoding directory")
        pos = self.pages + i * self.page_size
        end = pos + self.page_size
        page = self.encoding[pos:end]
        digest = self.encoding[self.directory + i * 32 + 16:self.directory + i * 32 + 32]
        require(hashlib.md5(page).digest() == digest, "encoding page checksum mismatch")
        while pos + 22 <= end:
            count = int.from_bytes(self.encoding[pos:pos + 2], 'little')
            if not count:
                break
            require(pos + 22 + count * 16 <= end, "encoding entry overflows page")
            if self.encoding[pos + 6:pos + 22] == key:
                failures = []
                for j in range(count):
                    try:
                        raw = self.ekey(self.encoding[pos + 22 + j * 16:pos + 38 + j * 16])
                        require(hashlib.md5(raw).digest() == key, "decoded CKey mismatch")
                        return raw
                    except EvidenceUnavailable as exc:
                        failures.append(str(exc))
                raise EvidenceUnavailable('; '.join(failures))
            pos += 22 + count * 16
        raise EvidenceUnavailable("CKey missing from encoding manifest: " + key.hex())

    def file(self, fid, kind):
        for ids, pos, _, _ in self.groups:
            i = bisect_left(ids, fid)
            if i < len(ids) and ids[i] == fid:
                key = self.root[pos + i * 16:pos + i * 16 + 16]
                raw = self.ckey(key)
                self.manifest[str(fid)] = dict(kind=kind, ckey=key.hex(), bytes=len(raw),
                                              sha256=hashlib.sha256(raw).hexdigest())
                return raw
        raise EvidenceUnavailable("FDID absent from local build root: " + str(fid))
