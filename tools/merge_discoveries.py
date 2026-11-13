#!/usr/bin/env python3
"""Merge a WTL1 export into the player-observation layer, offline.

Usage: python3 tools/merge_discoveries.py export.wtl [--check] [--report out.json]
Only Forever.lua is written. Curated/client/raw layers are never inputs or
outputs. Review the report, then retire observed reference-only IDs from
tools/reference_ids.tsv and regenerate ReferenceData.lua (docs/data-audit.md).

Learn.lua is the format authority: N name/hostile/level/services/spots/fac/title;
O name/spots; Q title/level/giver/ender/area/text/objectives[/needs/fac];
I name/drops/sellers; M spots; C kind/id/wrong/right. Coordinates are integers
0..1000, not percentages. Quest areas are observations, never inferred from
givers, objectives or Classic data. Earlier nonempty scalar fields win, as in
Learn.Import. Existing spots remain intact, including historical close pairs;
new spots use AddSpot's 1% cells, 30 spots/map and 20 maps/entry. Encounter order
is significant (first observed spot wins); records/maps/references serialize
in stable order. Invalid incoming records are rejected whole, with reasons,
rather than Learn.Import's permissive substring parsing. Unknown services are
ignored, just as in Learn.Import. IDs follow Core.Int/ParseGUID's signed-31-bit
entry-ID sanity bound; no arbitrary ceiling excludes new Forever creatures.
"""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BLOCK = re.compile(r"WaypointTrackerData\.forever\s*=\s*\[==\[(.*?)\]==\]", re.S)
SERVICES = set("vendor repair flight trainer banker innkeeper auctioneer stablemaster spirithealer".split())
SERVICES.update("trainer_class_" + key for key in "warrior paladin hunter rogue priest shaman mage warlock druid".split())
SERVICES.update("trainer_profession_" + key for key in "alchemy blacksmithing enchanting engineering herbalism leatherworking mining skinning tailoring cooking firstaid fishing".split())
SERVICES.update(("trainer_weapon", "trainer_riding"))
WIDTHS = {"N": (7, 9), "O": (4, 4), "Q": (3, 11), "I": (4, 5), "M": (2, 2), "C": (5, 5)}
LIMITS = {"N": 20000, "O": 20000, "Q": 20000, "I": 40000}


def integer(value):
    if not re.fullmatch(r"[0-9]+", value) or not 0 < int(value) < 2147483648:
        raise ValueError("invalid entry ID (expected 1..2147483647)")
    return str(int(value))


def clean(value, limit=200):
    value = re.sub(r"[\x00-\x1f\x7f]", " ", value)
    value = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", value)
    value = re.sub(r"\|H.*?\|h(.*?)\|h", r"\1", value)
    value = re.sub(r"\|[TA].*?\|[ta]", "", value).replace("|", "")
    raw = value.encode("utf-8")
    if len(raw) > limit:
        # Match CleanText's byte truncation, including its last-character trim.
        raw = raw[:limit].decode("utf-8", errors="ignore").encode("utf-8")
    return raw.decode("utf-8").strip(" \t\r\n\v\f")


def spots(value, maps, single=False):
    out = {}
    if not value:
        return out
    for chunk in value.split(";"):
        match = re.fullmatch(r"([0-9]+):([0-9]+(?:,[0-9]+)+)", chunk)
        if not match:
            raise ValueError("malformed coordinates")
        mid = int(integer(match[1]))
        if mid not in maps:
            raise ValueError("unknown uiMap %d" % mid)
        nums = list(map(int, match[2].split(",")))
        if len(nums) % 2 or any(n > 1000 for n in nums):
            raise ValueError("bogus coordinates (expected pairs in 0..1000)")
        out.setdefault(mid, []).extend(zip(nums[::2], nums[1::2]))
    if single and sum(map(len, out.values())) != 1:
        raise ValueError("expected one observed position")
    return out


def spots_text(value):
    return ";".join("%d:%s" % (mid, ",".join(str(n) for p in value[mid] for n in p))
                    for mid in sorted(value))


def refs(value, kinds):
    if not value:
        return ""
    result = []
    for ref in value.split(","):
        if not re.fullmatch("[" + kinds + "][0-9]+", ref):
            raise ValueError("invalid typed reference")
        value = ref[0] + integer(ref[1:])
        if value not in result:
            result.append(value)
    return ",".join(result)


def validate(fields, maps):
    f = list(fields)
    kind = f[0]
    if kind not in WIDTHS:
        raise ValueError("unknown record kind")
    low, high = WIDTHS[kind]
    if not low <= len(f) <= high:
        raise ValueError("wrong field count")
    f += [""] * (high - len(f))
    if kind in LIMITS:
        f[1] = integer(f[1])
        f[2] = clean(f[2])
    if kind == "N":
        if f[3] not in ("", "0", "1") or f[7] not in ("", "H", "A", "AH"):
            raise ValueError("invalid hostility/faction flag")
        f[4] = integer(f[4]) if f[4] else ""
        f[5] = ",".join(sorted(set(f[5].split(",")) & SERVICES))
        spots(f[6], maps)
        f[8] = clean(f[8], 60)
    elif kind == "O":
        spots(f[3], maps)
    elif kind == "Q":
        f[3] = integer(f[3]) if f[3] else ""
        f[4], f[5] = refs(f[4], "UO"), refs(f[5], "UO")
        f[6] = spots_text(spots(f[6], maps, single=True))
        f[7] = clean(f[7], 1000)
        f[8] = "|".join([s for s in (clean(o) for o in f[8].split("|")) if s][:10])
        f[9] = refs(f[9], "IUO")
        if f[10] not in ("", "H", "A"):
            raise ValueError("invalid faction flag")
    elif kind == "I":
        f[3], f[4] = refs(f[3], "UO"), refs(f[4], "U")
    elif kind == "M":
        spots(f[1], maps)
    elif kind == "C":
        if f[1] not in ("N", "O"):
            raise ValueError("invalid correction kind")
        f[2] = integer(f[2])
        f[3], f[4] = (spots_text(spots(v, maps, single=True)) for v in f[3:5])
        if not (f[3] or f[4]):
            raise ValueError("empty correction")
    return f


def export_rows(text):
    """Accept raw exports or a pasted GitHub issue, without reading its prose."""
    active = False
    for number, line in enumerate(text.splitlines(), 1):
        if line.startswith("WTL1\t"):
            active = True
        elif active and "\t" in line:
            yield number, line.split("\t")
    if not active:
        raise ValueError("WTL1 header missing")


def merge_spots(old, new, maps, stats, kind, existing):
    kept = spots(old, maps)
    for mid, points in spots(new, maps).items():
        for x, y in points:
            # Do the same floating-point operations as Lua AddSpot, including
            # boundary rounding, rather than assuming integer // 10 agrees.
            cell = lambda p: (int((p[0] / 1000) * 100), int((p[1] / 1000) * 100))
            if cell((x, y)) in {cell(p) for p in kept.get(mid, [])}:
                stats["positions_deduplicated"] += 1
                continue
            if (mid not in kept and len(kept) >= 20) or len(kept.get(mid, [])) >= 30:
                stats["positions_limited"] += 1
                continue
            kept.setdefault(mid, []).append((x, y))
            stats["positions_added"] += 1
            stats["positions_added_" + kind] += 1
            if existing:
                stats["positions_merged_existing"] += 1
    return spots_text(kept)


def union(old, new, limit=None):
    kept = list(dict.fromkeys(filter(None, old.split(","))))
    for value in dict.fromkeys(filter(None, new.split(","))):
        if value not in kept and (limit is None or len(kept) < limit):
            kept.append(value)
    return ",".join(sorted(kept))


def merge(source, incoming, maps):
    match = BLOCK.search(source)
    if not match:
        raise ValueError("Forever.lua WTL1 block missing")
    records, corrections = {}, []
    for _, f in export_rows(match[1]):
        if f[0] == "C":
            corrections.append(f)
        else:
            key = (f[0], f[1] if f[0] != "M" else "")
            if key in records:
                raise ValueError("duplicate existing entry: " + str(key))
            records[key] = f
    stats = Counter()
    rejected = []
    counts = Counter(k[0] for k in records)
    for number, raw in export_rows(incoming):
        try:
            if any("]==]" in v for v in raw):
                raise ValueError("unsafe Lua long-string delimiter")
            f = validate(raw, maps)
            if any("]==]" in v for v in f):
                raise ValueError("unsafe Lua long-string delimiter after text cleaning")
            kind = f[0]
            if kind == "C":
                candidates = [c for c in corrections if c[1:3] == f[1:3]]
                def same(a, b):
                    if not a or not b:
                        return False
                    ma, pa = next(iter(spots(a, maps).items()))
                    mb, pb = next(iter(spots(b, maps).items()))
                    return ma == mb and all(abs(x / 1000 - y / 1000) <= .02 for x, y in zip(pa[0], pb[0]))
                replaced = [c for c in candidates if same(c[3], f[3]) or
                            (not c[3] and not f[3] and same(c[4], f[4]))]
                if not replaced and (len(candidates) >= 5 or
                        (not candidates and len({tuple(c[1:3]) for c in corrections}) >= 1000)):
                    raise ValueError("correction limit")
                corrections = [c for c in corrections if c not in replaced] + [f]
                stats["accepted_C"] += 1
                continue
            key = (kind, f[1] if kind != "M" else "")
            existing = key in records
            if not existing and kind in LIMITS and counts[kind] >= LIMITS[kind]:
                raise ValueError("entry limit")
            old = records.get(key, [kind, f[1]] if kind != "M" else [kind])[:]
            old += [""] * (len(f) - len(old))
            special = {"N": {5, 6}, "O": {3}, "Q": {6, 9}, "I": {3, 4}, "M": {1}}[kind]
            for ix in range(1 if kind == "M" else 2, len(f)):
                if ix not in special and not old[ix]:
                    old[ix] = f[ix]
            if kind in ("N", "O", "M"):
                ix = {"N": 6, "O": 3, "M": 1}[kind]
                old[ix] = merge_spots(old[ix], f[ix], maps, stats, kind, existing)
            if kind == "N":
                old[5] = union(old[5], f[5])
                if any(token == "trainer" or token.startswith("trainer_") for token in old[5].split(",")):
                    old[7] = "".join(letter for letter in "AH" if letter in old[7] + f[7])
            elif kind == "Q":
                if not old[6] and f[6]:
                    old[6] = f[6]
                    stats["positions_added"] += 1
                    stats["positions_added_Q"] += 1
                    stats["positions_merged_existing"] += int(existing)
                old[9] = union(old[9], f[9], 40)
            elif kind == "I":
                old[3], old[4] = union(old[3], f[3], 40), union(old[4], f[4], 20)
            records[key] = old
            if not existing:
                counts[kind] += 1
                stats["added_" + kind] += 1
            stats["accepted_" + kind] += 1
        except ValueError as exc:
            label = raw[:3] if raw[0] == "C" else raw[:2]
            rejected.append({"line": number, "entry": "".join(label), "reason": str(exc)})
    def order(key):
        return key[0], int(key[1] or 0)
    lines = ["WTL1\tcommunity\t1"]
    for key in sorted(records, key=order):
        f = records[key][:]
        # Empty position columns are structural, including on quarantined
        # NPCs. The reviewed position filter indexes them unconditionally.
        minimum = {"N": 7, "O": 4, "Q": 3, "I": 4, "M": 2}[key[0]]
        f += [""] * max(0, minimum - len(f))
        while len(f) > minimum and not f[-1]:
            f.pop()
        lines.append("\t".join(f))
    lines += ["\t".join(c) for c in sorted(corrections, key=lambda c: (c[1], int(c[2]), c[3], c[4]))]
    body = "\n" + "\n".join(lines) + "\n"
    return source[:match.start(1)] + body + source[match.end(1):], {
        "counts": dict(sorted(stats.items())), "rejected": rejected,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("--forever", type=Path, default=ROOT / "WaypointTracker_Data/Forever.lua")
    parser.add_argument("--maps", type=Path, default=ROOT / "tools/fixtures/travel/UiMap.csv")
    parser.add_argument("--check", action="store_true", help="report without writing Forever.lua")
    parser.add_argument("--report", type=Path, help="write machine-readable counts and rejections")
    args = parser.parse_args()
    with args.maps.open(encoding="utf-8-sig", newline="") as handle:
        maps = {int(row["ID"]) for row in csv.DictReader(handle)}
    result, report = merge(args.forever.read_text(encoding="utf-8"),
                           args.export.read_text(encoding="utf-8"), maps)
    if not args.check:
        args.forever.write_text(result, encoding="utf-8")
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
