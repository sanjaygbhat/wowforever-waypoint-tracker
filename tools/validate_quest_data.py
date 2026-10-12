#!/usr/bin/env python3
"""Offline audit of all bundled quest/NPC/object/item location layers.

Run from any directory: python3 tools/validate_quest_data.py
Optional: --client-cache DIR (wago CSV cache), --show-all, --max-issues 30.
No downloads, addon loading, writes, or third-party Python packages.
Missing references are internal completeness errors, NOT claims that IDs do
not exist in the game. Differences from classic positions are only suspects.
"""
import argparse
import collections
import csv
import gzip
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LONG = re.compile(r"(\w+(?:\.\w+)*)\s*=\s*\[(=*)\[(.*?)\]\2\]", re.S)
KIND = {"N": "units", "O": "objects", "Q": "quests", "I": "items"}
REF = {"U": "units", "O": "objects", "I": "items"}
LOCALES = ("deDE", "frFR", "esES", "ptBR", "ruRU", "koKR", "zhCN", "zhTW")
# Classic Era bounds also documented in Database.lua; raw Data.lua is Classic.
OLD = {1412: (1, -3697.9165, -3089.5833, -272.9167, 2047.9166),
       1423: (0, 1218.75, -6056.25, 3799.9998, -2185.4165),
       1433: (0, -10022.916, -3741.6665, -8575, -1570.8332),
       1453: (0, -9175.205, 36.7006, -8278.8506, 1380.9714)}


def read_blocks(path):
    text = path.read_text(encoding="utf-8")
    out = []
    for m in LONG.finditer(text):
        first = text.count("\n", 0, m.start(3)) + 1
        rows = [(first + i, line.split("\t"))
                for i, line in enumerate(m[3].splitlines()) if line]
        out.append((m[1], rows))
    return out


def csv_open(path):
    if not path.exists() and path.with_name(path.name + ".gz").exists():
        path = path.with_name(path.name + ".gz")
    return gzip.open(path, "rt", encoding="utf-8-sig", newline="") if path.suffix == ".gz" else path.open(encoding="utf-8-sig", newline="")


def csv_rows(path):
    with csv_open(path) as f:
        return list(csv.DictReader(f))


class Audit:
    def __init__(self):
        self.errors = []
        self.suspects = []
        self.stats = collections.Counter()

    def fail(self, category, file, line, entry, value, why):
        self.errors.append((category, file, line, str(entry), str(value), why))

    def suspect(self, category, file, line, entry, value, why):
        self.suspects.append((category, file, line, str(entry), str(value), why))

    def unique(self, rows, file, label, ix=0):
        seen = {}
        for line, f in rows:
            key = f[ix]
            if key in seen:
                self.fail("duplicate", file, line, label + " " + key, f,
                          "duplicate ID; first defined on line %d" % seen[key])
            seen[key] = line
        return seen

    def coords(self, value, file, line, entry, maps, areas=False):
        points = []
        seen = set()
        for chunk in value.split(";"):
            if not chunk:
                continue
            match = re.fullmatch(r"([1-9][0-9]*):([0-9]+(?:,[0-9]+)+)", chunk)
            if not match:
                self.fail("coordinate-schema", file, line, entry, chunk,
                          "expected map/area:x,y pairs in tenths of a percent")
                continue
            mid, vals = int(match[1]), list(map(int, match[2].split(",")))
            if mid not in maps:
                self.fail("unknown-area" if areas else "unknown-map", file, line,
                          entry, mid, "ID absent from " + ("English zone table" if areas else "client UiMap.csv"))
            if len(vals) % 2:
                self.fail("coordinate-schema", file, line, entry, chunk, "odd number of x/y values")
            for x, y in zip(vals[::2], vals[1::2]):
                self.stats["coordinate_pairs"] += 1
                if not (0 <= x <= 1000 and 0 <= y <= 1000):
                    self.fail("coordinate-range", file, line, entry, (mid, x, y),
                              "x/y must be 0..1000 (0..100 percent)")
                if (mid, x, y) in seen:
                    self.suspect("duplicate-point", file, line, entry, (mid, x, y), "same encoded point repeated")
                seen.add((mid, x, y))
                points.append((mid, x / 1000, y / 1000))
        return points


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, default=ROOT)
    ap.add_argument("--geometry-cache", type=Path)
    ap.add_argument("--client-cache", type=Path, default=ROOT / "tools/fixtures/client")
    ap.add_argument("--show-all", action="store_true")
    ap.add_argument("--max-issues", type=int, default=30)
    args = ap.parse_args()
    root = args.repo.resolve()
    data = root / "WaypointTracker_Data"
    cache = args.geometry_cache or root / "tools/fixtures/travel"
    a = Audit()
    files = sorted(p for p in data.glob("*.lua") if p.stem != "RouteSeeds")
    blocks = {p.stem: read_blocks(p) for p in files}
    if any(not b for b in blocks.values()):
        raise ValueError("could not parse one or more bundled Lua long-string tables")
    raw = dict(blocks["Data"])
    names = dict(blocks["Names_enUS"])
    ui = {int(r["ID"]): r for r in csv_rows(cache / "UiMap.csv")}
    geometry = {}
    for r in csv_rows(cache / "UiMapAssignment.csv"):
        m = int(r["UiMapID"])
        if m not in geometry and [float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")] == [0, 0, 1, 1]:
            geometry[m] = (int(r["MapID"]), *(float(r[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4")))
    areas = {int(f[0]) for _, f in names["zones"]}
    ids = {k: {f[0] for _, f in raw[k]} for k in KIND.values()}
    # All definitions, including later discovery layers and named source items.
    for stem in ("Curated", "Forever", "ReferenceData"):
        for _, rows in blocks[stem]:
            for line, f in rows:
                if f[0] in KIND:
                    ids[KIND[f[0]]].add(f[1])
    # Client-only quests are intentionally named asynchronously by Learn.lua.
    # ForeverQuests.lua supplies their definitions; do not report them dangling.
    fq = (root / "WaypointTracker/ForeverQuests.lua").read_text(encoding="utf-8")
    match = re.search(r'foreverQuests\s*=\s*"([0-9,]+)"', fq)
    if not match:
        raise ValueError("cannot parse ForeverQuests.lua client quest ID roster")
    ids["quests"].update(match[1].split(","))
    item_names = {f[0] for _, f in names["items"]}
    item_names.update(f[0] for _, f in blocks["Sources"][-1][1])
    item_names.update(f[0] for _, f in blocks["Items_enUS"][0][1] if len(f) > 1 and f[1])
    ids["items"].update(item_names)

    def reference(file, line, entry, field, value, typ=None):
        if typ:
            if value and not re.fullmatch(r"[1-9][0-9]*(?:,[1-9][0-9]*)*", value):
                a.fail("reference-schema", file, line, entry, value, "invalid " + field + " ID list")
            refs = [(typ, x) for x in value.split(",") if x]
        else:
            if value and not re.fullmatch(r"[UOI][1-9][0-9]*(?:,[UOI][1-9][0-9]*)*", value):
                a.fail("reference-schema", file, line, entry, value, "invalid " + field + " typed references")
            refs = re.findall(r"([UOI])([0-9]+)", value)
        for kind, rid in refs:
            a.stats["references"] += 1
            if rid not in ids[REF[kind]]:
                a.fail("dangling:" + file + ":" + field, file, line, entry,
                       kind + rid, "undefined in every bundled " + REF[kind] + " layer; field " + field)

    positions = {}
    faction_records = {}
    hubs = set()
    for kind, width in (("units", 5), ("objects", 3), ("quests", 12), ("items", 4), ("services", 2)):
        rows = raw[kind]
        a.stats["raw_" + kind] = len(rows)
        a.unique(rows, "Data.lua", kind)
        for line, f in rows:
            entry = kind + " " + f[0]
            if len(f) != width:
                a.fail("schema", "Data.lua", line, entry, len(f), "expected %d TSV fields" % width)
                continue
            if kind in ("units", "objects"):
                fac = f[2 if kind == "units" else 1]
                if fac not in ("", "A", "H", "AH"):
                    a.fail("faction", "Data.lua", line, entry, fac, "expected empty/A/H/AH")
                faction_records[(kind, f[0])] = fac
                positions[(kind, f[0])] = a.coords(f[4 if kind == "units" else 2], "Data.lua", line, entry, areas, True)
            elif kind == "quests":
                for ix, field, typ in ((5, "giverU", "U"), (6, "giverO", "O"), (7, "enderU", "U"), (8, "enderO", "O"), (9, "objectiveU", "U"), (10, "objectiveO", "O"), (11, "objectiveI", "I")):
                    reference("Data.lua", line, entry, field, f[ix], typ)
                    if ix in (5, 6, 7, 8):
                        hubs.update((REF[typ], rid) for rid in f[ix].split(",") if rid)
            elif kind == "items":
                for ix, field, typ in ((1, "dropU", "U"), (2, "dropO", "O"), (3, "vendorU", "U")):
                    reference("Data.lua", line, entry, field, f[ix], typ)
            else:
                for token in f[1].split(","):
                    if not token:
                        continue
                    m = re.fullmatch(r"(-?[1-9][0-9]*):(A?H?)", token)
                    if not m:
                        a.fail("service-schema", "Data.lua", line, entry, token, "expected signedID:faction")
                    else:
                        reference("Data.lua", line, entry, "service", str(abs(int(m[1]))), "O" if int(m[1]) < 0 else "U")
    # Complete ID parity for Names, Items and Sources (fallback does not excuse gaps).
    for family, base in (("Names", "Names_enUS"), ("Items", "Items_enUS"), ("Sources", "Sources")):
        base_blocks = blocks[base] if family == "Names" else blocks[base][-1:]
        locales = (*LOCALES, "esMX") if family == "Items" else LOCALES
        for loc in locales:
            filename = family + "_" + loc + ".lua"
            theirs = blocks[family + "_" + loc]
            for (label, en), (_, translated) in zip(base_blocks, theirs):
                en_ids = {f[0] for _, f in en}
                got = a.unique(translated, filename, label)
                for missing in sorted(en_ids - got.keys(), key=int):
                    a.fail("locale-missing:" + filename, filename, 1, label + " " + missing, "absent", "ID exists in " + base + ".lua; runtime falls back to English")
                for extra in sorted(got.keys() - en_ids, key=int):
                    a.fail("locale-extra", filename, got[extra], label + " " + extra, "extra ID", "absent from English base")
                for line, f in translated:
                    if len(f) < 2 or (family != "Items" and not f[1]):
                        a.fail("locale-empty", filename, line, label + " " + f[0], f, "missing display name")
        if family == "Names":
            for label, en in base_blocks:
                a.unique(en, base + ".lua", label)
                if label in raw:
                    for missing in sorted({f[0] for _, f in raw[label]} - {f[0] for _, f in en}, key=int):
                        a.fail("missing-English-name", base + ".lua", 1, label + " " + missing, "absent", "raw entry is skipped by Database.Parse")

    # Compare in world yards, using old bounds for raw Classic percentages.
    # This deliberately does not choose the smallest overlapping rectangle.
    area_ui = {}
    for _, f in names["zones"]:
        matches = [mid for mid, r in ui.items() if r["Name_lang"] == f[1] and r["Type"] == "3"]
        if matches:
            area_ui[int(f[0])] = min(matches)
    def world(mid, x, y, classic=False):
        b = OLD.get(mid, geometry.get(mid)) if classic else geometry.get(mid)
        return (b[0], b[3]-y*(b[3]-b[1]), b[4]-x*(b[4]-b[2])) if b else None
    prior_world = {}
    for key, spots in positions.items():
        prior_world[key] = [w for mid,x,y in spots
                            if (w := world(area_ui.get(mid), x, y, True))]
    for stem in ("Curated", "Forever", "ReferenceData"):
        file = stem + ".lua"
        seen = {}
        for _, rows in blocks[stem]:
            for line, f in rows:
                kind = f[0]
                if kind == "WTL1":
                    continue
                if kind == "M":
                    a.coords(f[1], file, line, "mailboxes", ui)
                    continue
                if kind not in KIND or len(f) < 3:
                    a.fail("discovery-schema", file, line, kind, f, "unknown or incomplete discovery row")
                    continue
                entry = kind + f[1]
                a.stats[stem + "_" + kind] += 1
                if entry in seen:
                    a.fail("duplicate", file, line, entry, f, "first definition at line %d" % seen[entry])
                seen[entry] = line
                fac_ix = 7 if kind == "N" else 10 if kind == "Q" else None
                if fac_ix is not None and len(f) > fac_ix and f[fac_ix] not in ("", "A", "H"):
                    a.fail("faction", file, line, entry, f[fac_ix], "expected empty/A/H")
                coord_ix = {"N": 6, "O": 3, "Q": 6}.get(kind)
                if coord_ix is not None and len(f) > coord_ix:
                    spots = a.coords(f[coord_ix], file, line, entry, ui)
                    key = (KIND[kind], f[1])
                    original = prior_world.get(key, [])
                    if kind in ("N", "O") and original:
                        for mid,x,y in spots:
                            w = world(mid, x, y)
                            if not w:
                                continue
                            dist = [math.hypot(w[1]-v[1], w[2]-v[2]) for v in original if w[0] == v[0]]
                            if not dist or min(dist) > 500:
                                a.suspect("world-divergence-hub" if key in hubs else "world-divergence", file, line,
                                          entry, "%s:%.1f,%.1f" % (mid,x*100,y*100),
                                          ("nearest Classic spawn %.0f yards away" % min(dist) if dist else "no Classic spawn on this continent") + "; may be a legitimate Forever move, patrol or instance; verify in game")
                    original_fac = faction_records.get(key)
                    if fac_ix is not None and len(f) > fac_ix and original_fac in ("A", "H") and f[fac_ix] in ("A", "H") and original_fac != f[fac_ix]:
                        a.suspect("faction-conflict", file, line, entry, f[fac_ix], "raw Classic faction is " + original_fac + "; verify Forever allegiance")
                if kind in ("Q", "I"):
                    for ix, field in (((4, "giver"), (5, "ender"), (9, "needs")) if kind == "Q" else ((3, "drops"), (4, "vendors"))):
                        if len(f) > ix:
                            reference(file, line, entry, field, f[ix])
    for line, f in blocks["Sources"][0][1]:
        for ix, field, typ in ((1, "dropU", "U"), (2, "dropO", "O"), (3, "vendorU", "U")):
            reference("Sources.lua", line, "I" + f[0], field, f[ix], typ)
    for line, f in blocks["Items"][0][1]:
        if len(f) != 8:
            a.fail("schema", "Items.lua", line, "I" + f[0], len(f), "expected 8 TSV fields")
        elif f[6]:
            if f[6] not in ids["quests"]:
                a.fail("dangling:Items.lua:startsQuest", "Items.lua", line, "I" + f[0], f[6], "starts quest undefined in all quest layers")

    # Client uses world coordinates; never enforce percent bounds on those.
    cb = blocks["Client"]
    for label, rows in cb[:3]:
        for line, f in rows:
            qi = label == "pois"
            ix = 2 if qi else 1
            entry = ("Q" if qi else label + " ") + f[0]
            cont, mid = int(f[ix]), int(f[ix+1])
            wx, wy = float(f[ix+2]), float(f[ix+3])
            if not math.isfinite(wx) or not math.isfinite(wy):
                a.fail("world-coordinate", "Client.lua", line, entry, (wx, wy), "world coordinates must be finite")
            b = geometry.get(mid)
            if mid and mid not in ui:
                a.fail("unknown-map", "Client.lua", line, entry, mid, "not in client UiMap table")
            elif b and (b[0] != cont or not (b[1]-.1 <= wx <= b[3]+.1 and b[2]-.1 <= wy <= b[4]+.1)):
                a.fail("world-map-mismatch", "Client.lua", line, entry, (cont, mid, wx, wy), "world point outside declared map or on different continent")
            if qi and f[0] not in ids["quests"]:
                a.fail("dangling:Client.lua:quest", "Client.lua", line, entry, f[0], "marker quest has no bundled quest definition")
            a.stats["client_" + label] += 1
    for i in range(3, len(cb), 2):
        for j, label in enumerate(("flights", "towns")):
            expected = {f[0] for _, f in cb[j+1][1]}
            got = {f[0] for _, f in cb[i+j][1]}
            if got != expected:
                a.fail("client-locale-parity", "Client.lua", cb[i+j][1][0][0], label, sorted(expected-got), "localized client names must match position IDs")
    if args.client_cache:
        verify_client_source(a, cb, args.client_cache, blocks)
    else:
        print("NOTE: DB2 provenance check not run; pass --client-cache DIR for cached QuestPOI/TaxiNodes/AreaPOI CSVs")
    # These exact retained relationships are deliberately non-routable. New
    # missing relationships and obsolete exceptions fail; no category wildcard.
    exceptions = {}
    exception_path = root / "tools/nonroutable_references.tsv"
    for row in exception_path.read_text().splitlines():
        if not row or row.startswith("#"):
            continue
        cat, file, entry, target, reason = row.split("\t")
        key = (cat, file, entry, target)
        if key in exceptions or not reason:
            raise ValueError("invalid/duplicate non-routable exception " + str(key))
        exceptions[key] = reason
    found, remaining = set(), []
    for error in a.errors:
        key = (error[0], error[1], error[3], error[4])
        if key in exceptions:
            found.add(key)
        else:
            remaining.append(error)
    a.errors = remaining
    for key in sorted(exceptions.keys() - found):
        a.fail("stale-non-routable", key[1], 1, key[2], key[3],
               "relationship now resolves or disappeared; remove its exact exception")
    print("REVIEW: %d exact non-routable relationships retained; source/reason in tools/nonroutable_references.tsv" % len(found))
    print("SCOPE: %d Lua files; %s" % (len(files), "; ".join("%s=%s" % x for x in sorted(a.stats.items()))))
    counts = collections.Counter(e[0] for e in a.errors)
    print("ERROR COUNTS: " + "; ".join("%s=%d" % x for x in sorted(counts.items())))
    limit = len(a.errors) if args.show_all else max(0, args.max_issues)
    for cat, file, line, entry, value, why in a.errors[:limit]:
        print("FAIL [%s] WaypointTracker_Data/%s:%d %s value=%s: %s" % (cat, file, line, entry, value, why))
    if len(a.errors) > limit:
        print("%d additional errors; use --show-all for every file/line/entry/value" % (len(a.errors)-limit))
    print("SUSPECT COUNTS: " + str(dict(sorted(collections.Counter(e[0] for e in a.suspects).items()))))
    for cat, file, line, entry, value, why in a.suspects[:len(a.suspects) if args.show_all else max(0, args.max_issues)]:
        print("SUSPECT [%s] WaypointTracker_Data/%s:%d %s value=%s: %s" % (cat, file, line, entry, value, why))
    print("RESULT: %d errors, %d suspects" % (len(a.errors), len(a.suspects)))
    return 1 if a.errors else 0


def verify_client_source(a, blocks, cache, all_blocks):
    builds = sorted(cache.glob("QuestPOIBlob-*-enUS.csv"))
    if not builds:
        raise ValueError("client cache lacks QuestPOIBlob-<build>-enUS.csv")
    # Installed build, when present; otherwise lexical latest cache build.
    preferred = cache / "QuestPOIBlob-1.60.1.70338-enUS.csv"
    build = (preferred if preferred.exists() else builds[-1]).name[len("QuestPOIBlob-"):-len("-enUS.csv")]
    def table(name):
        return csv_rows(cache / (name + "-" + build + "-enUS.csv"))
    points = collections.defaultdict(list)
    for p in table("QuestPOIPoint"):
        points[p["QuestPOIBlobID"]].append((float(p["X"]), float(p["Y"])))
    expected = set()
    for b in table("QuestPOIBlob"):
        pts = points[b["ID"]]
        if not pts or b["Flags"] not in ("", "0"):
            continue
        idx = int(b["ObjectiveIndex"])
        step = "end" if idx == -1 else "start" if idx == 32 else "obj%d" % idx if 0 <= idx < 32 else None
        if step:
            expected.add((b["QuestID"], step, b["MapID"], b["UiMapID"],
                          "%.1f" % (sum(x for x,y in pts)/len(pts)),
                          "%.1f" % (sum(y for x,y in pts)/len(pts))))
    current = {tuple(f) for _, f in blocks[0][1]}
    for line, f in blocks[0][1]:
        if tuple(f) not in expected:
            a.fail("DB2-POI-provenance", "Client.lua", line, "Q" + f[0], f, "absent from QuestPOIBlob/QuestPOIPoint " + build)
    for f in sorted(expected-current):
        a.fail("DB2-POI-missing", "Client.lua", 1, "Q" + f[0], f, "current client DB2 marker missing from bundle " + build)
    maps = {r["ID"]: r for r in table("UiMap")}
    # Zone ownership is explicit in TaxiNodes names. A containing map rectangle
    # proves projection validity, not semantic ownership (Hillsbrad/Alterac).
    def normalize(name):
        return re.sub(r"[^a-z]", "", name.lower())
    map_by_name = {normalize(r["Name_lang"]): r["ID"] for r in maps.values() if r["Type"] == "3"}
    map_by_name["hillsbrad"] = map_by_name.get("hillsbradfoothills")
    for label, table_name, rows in (("flights", "TaxiNodes", blocks[1][1]), ("towns", "AreaPOI", blocks[2][1])):
        source = {r["ID"]: r for r in table(table_name)}
        for line, f in rows:
            r = source.get(f[0])
            if not r or any(f[ix] != value for ix,value in ((1, r["ContinentID"] if r else ""), (3, "%.1f" % float(r["Pos_0"]) if r else ""), (4, "%.1f" % float(r["Pos_1"]) if r else ""))):
                a.fail("DB2-world-provenance", "Client.lua", line, label + " " + f[0], f, "world position differs from " + table_name + " " + build)
            if r and label == "flights":
                zone = r["Name_lang"].rsplit(", ", 1)[-1] if ", " in r["Name_lang"] else ""
                canonical = map_by_name.get(normalize(zone))
                named_city = maps.get(f[2], {}).get("Name_lang") == r["Name_lang"].split(", ", 1)[0]
                if canonical and f[2] != canonical and not named_city:
                    a.fail("DB2-taxi-map-ownership", "Client.lua", line, "taxi " + f[0], f[2],
                           "TaxiNodes name '%s' requires UiMap %s (%s); keep world coordinates unchanged" % (r["Name_lang"], canonical, zone))
                flags = int(r["Flags"] or 0)
                fac = ("A" if flags & 1 else "") + ("H" if flags & 2 else "")
                if f[5] != fac:
                    a.fail("DB2-faction", "Client.lua", line, label + " " + f[0], f[5], "TaxiNodes faction flags require " + fac)
    item_rows = all_blocks["Items"][0][1]
    wanted = {f[0] for _, f in item_rows}
    wanted.update(f[0] for loc in ("enUS", *LOCALES, "esMX") for _,f in all_blocks["Items_"+loc][0][1])
    def selected_table(name, loc="enUS"):
        # Stream large ItemSparse tables: retain only IDs the bundle uses.
        with csv_open(cache / (name+"-"+build+"-"+loc+".csv")) as handle:
            return {r["ID"]: r for r in csv.DictReader(handle) if r["ID"] in wanted}
    sparse = selected_table("ItemSparse")
    classes = selected_table("Item")
    for line, f in item_rows:
        r, c = sparse.get(f[0]), classes.get(f[0])
        expected = [c["ClassID"], c["SubclassID"], r["OverallQualityID"], r["ItemLevel"], r["RequiredLevel"], r["StartQuestID"] if r["StartQuestID"] != "0" else ""] if r and c else None
        if not expected or f[1:7] != expected:
            a.fail("DB2-item-metadata", "Items.lua", line, "I"+f[0], f[1:7], "Item/ItemSparse %s requires %s" % (build, expected))
    item_text_count = 0
    for loc in ("enUS", *LOCALES, "esMX"):
        localized = sparse if loc == "enUS" else selected_table("ItemSparse", loc)
        for line, f in all_blocks["Items_"+loc][0][1]:
            item_text_count += 1
            r = localized.get(f[0])
            expected = [r["Display_lang"].replace("\t", " ").replace("\n", " ").replace("\r", " ").replace("]]", "] ]").strip() if f[1] else "", r["Description_lang"].replace("\t", " ").replace("\n", " ").replace("\r", " ").replace("]]", "] ]").strip()] if r else None
            if expected is None or f[1:3] != expected:
                a.fail("DB2-item-locale", "Items_"+loc+".lua", line, "I"+f[0], f[1:3], "ItemSparse %s %s requires %s" % (build, loc, expected))
    previous = cache / "ItemSparse-1.60.1.70205-enUS.csv"
    if (previous.exists() or previous.with_name(previous.name + ".gz").exists()) and build != "1.60.1.70205":
        with csv_open(previous) as handle:
            old_ids = {r["ID"] for r in csv.DictReader(handle)}
        with csv_open(cache / ("ItemSparse-"+build+"-enUS.csv")) as handle:
            for r in csv.DictReader(handle):
                if r["ID"] not in old_ids and r["ID"] not in wanted:
                    a.fail("DB2-new-item-missing", "Items.lua", 9, "I"+r["ID"], "absent", "new ItemSparse ID in installed build " + build + "; regenerate metadata and all locale names together")
    print("DB2 ITEMS: %d item metadata records and %d localized name/description records checked" % (len(item_rows), item_text_count))
    print("DB2 PROVENANCE: compared %d shipped POIs, %d flight positions/factions, %d town positions against cached build %s" % (len(blocks[0][1]), len(blocks[1][1]), len(blocks[2][1]), build))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, IndexError) as exc:
        print("FAIL [audit-input] " + str(exc), file=sys.stderr)
        sys.exit(2)
