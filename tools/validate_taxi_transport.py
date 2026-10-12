#!/usr/bin/env python3
"""Offline audit of shipped travel data against cached build-specific raw inputs.

Run: python3 tools/validate_taxi_transport.py
No generator imports, network, writes, or third-party Python packages. A missing
cache is a failure, never a successful skipped audit. --data/--cache accept other
snapshots. Geometry times check the declared 30 yd/s estimate, not live duration.
Special Nighthaven routes are dialog flights, not discoverable taxi-map routes:
Mapzeroth Data/Forever/Edges.lua documents their class and interaction rules.
"""
import argparse
import collections
import csv
import json
import math
from pathlib import Path
import re
import statistics
import sys

ROOT = Path(__file__).resolve().parents[1]
TRANSPORT = {"dock", "zeppelin", "tram", "portal", "teleport"}
RIDES = {"ship", "zeppelin", "tram", "portal", "transition"}
SPECIAL = {(62, 27): ("Alliance", "DRUID", 154),
           (63, 22): ("Horde", "DRUID", 544)}
TOWERS = {84, 85, 86, 87}  # ownership-controlled service, not ordinary taxi map
SKIP = re.compile(r"^(Transport|Generic|Quest Path|zzOLD|Programmer|Naxxramas)", re.I)
CITY_MAPS = {2: 1453, 6: 1455, 11: 1458, 22: 1456, 23: 1454}


def normalized(s):
    return re.sub(r"[^a-z]", "", s.lower())


def faction(r):
    bits = int(r["Flags"]) & 3
    if bits:
        return {1: "Alliance", 2: "Horde", 3: ""}[bits]
    h, a = int(r["MountCreatureID_0"]), int(r["MountCreatureID_1"])
    return "Horde" if h and not a else "Alliance" if a and not h else ""


class Audit:
    def __init__(self, data, cache, extra, tickets=None):
        self.data, self.cache, self.extra, self.tickets = data, cache, extra, tickets
        self.errors = self.warnings = self.checks = 0

    def label(self, path):
        try:
            return str(path.relative_to(ROOT))
        except ValueError:
            return str(path)

    def check(self, condition, line, entry, value, why):
        self.checks += 1
        if not condition:
            self.errors += 1
            print(f"FAIL {self.label(self.data)}:{line}: {entry}: value={value!r}; {why}")

    def warn(self, entry, why):
        self.warnings += 1
        print(f"WARN {entry}: {why}")

    def csv(self, name):
        with (self.cache / name).open(encoding="utf-8", newline="") as f:
            return list(csv.DictReader(f))

    def tsv(self, path):
        return [(i, line.split("\t")) for i, line in
                enumerate(path.read_text().splitlines(), 1)
                if line and not line.startswith("#")]

    def block(self, name, width):
        match = re.search(r"\b" + name + r"\s*=\s*\[\[\n(.*?)\n\]\]", self.text, re.S)
        if not match:
            raise ValueError(f"{self.data}: missing TSV block {name}")
        first = self.text.count("\n", 0, match.start(1)) + 1
        out = []
        for offset, line in enumerate(match[1].splitlines()):
            row = line.split("\t")
            optional = name in ("nodes", "links")
            extras = 2 if name == "nodes" else (1 if name == "links" else 0)
            valid = width <= len(row) <= width + extras
            self.check(valid, first + offset, name, len(row),
                       f"expected {width} TSV columns" + (" plus optional service/area flags" if optional else ""))
            if valid:
                if optional:
                    row += [""] * (width + extras - len(row))
                    self.check(row[width] in (("", "0", "1") if name == "nodes" else ("", "1")),
                               first + offset, name, row[width], "invalid optional discovery/dialog service flag")
                    if name == "nodes":
                        self.check(row[width + 1] in ("", "mapzeroth-indoor"),
                                   first + offset, name, row[width + 1], "invalid indoor area provenance flag")
                out.append((first + offset, row))
        return out

    def run(self):
        self.text = self.data.read_text()
        area_match = re.search(r"areas\s*=\s*\{(.*?)\}", self.text, re.S)
        if not area_match:
            raise ValueError("missing area dictionary")
        self.areas = re.findall(r'"([^"]+)"', area_match[1])
        nr, lr = self.block("nodes", 13), self.block("links", 11)
        self.nodes = {}
        for line, n in nr:
            self.check(n[0] not in self.nodes, line, n[0], n[0], "duplicate node ID")
            self.nodes[n[0]] = (line, n)
        maprows = self.block("maps", 2)
        regions = self.block("regions", 5)
        uimaps = {int(r["ID"]): r for r in self.csv("UiMap.csv")}
        maps_by_name = {normalized(r["Name_lang"]): i for i, r in uimaps.items()
                        if int(r["Type"]) == 3}
        assign = {}
        for r in self.csv("UiMapAssignment.csv"):
            if [float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")] == [0, 0, 1, 1]:
                assign.setdefault(int(r["UiMapID"]), r)

        def project(m, wx, wy):
            r = assign[m]
            x = (float(r["Region_4"]) - wy) / (float(r["Region_4"]) - float(r["Region_1"])) * 100
            y = (float(r["Region_3"]) - wx) / (float(r["Region_3"]) - float(r["Region_0"])) * 100
            return x, y

        taxis = {int(r["ID"]): r for r in self.csv("TaxiNodes.csv")}
        paths = self.csv("TaxiPath.csv")
        pointsets = collections.defaultdict(list)
        for r in self.csv("TaxiPathNode.csv"):
            pointsets[int(r["PathID"])].append(r)
        directed = collections.defaultdict(list)
        for line, l in lr:
            a, b = self.nodes.get(l[0]), self.nodes.get(l[1])
            self.check(bool(a and b), line, ">".join(l[:2]), l[:2], "link endpoint missing")
            self.check(l[6] in ("", "1"), line, ">".join(l[:2]), l[6], "oneway must be blank or 1")
            self.check(l[7] in ("", "Alliance", "Horde"), line, ">".join(l[:2]), l[7], "invalid faction token")
            if l[2] in RIDES | {"taxi", "lift"}:
                self.check(bool(l[3]) and math.isfinite(float(l[3])) and float(l[3]) > 0,
                           line, ">".join(l[:2]), l[3], "ride requires positive finite seconds")
            if l[4]:
                self.check(0 < float(l[4]) <= float(l[3]), line, ">".join(l[:2]), l[4], "aboard time must be positive and <= total estimate")
            self.check(not l[5] or (float(l[5]) >= 0 and float(l[5]).is_integer()),
                       line, ">".join(l[:2]), l[5], "loading-screen count must be a nonnegative integer")
            if a and b:
                if l[2] == "taxi":
                    self.check(a[1][3] == b[1][3] and a[1][11] and b[1][11],
                               line, ">".join(l[:2]), (a[1][3], b[1][3]), "taxi requires same-continent taxi endpoints")
                    fa, fb = a[1][12], b[1][12]
                    self.check(not (fa and fb and fa != fb), line, ">".join(l[:2]), (fa, fb), "hostile-faction endpoints")
                    self.check(not l[7] or l[7] in (fa, fb), line, ">".join(l[:2]), l[7], "link faction conflicts with endpoint factions")
                elif l[2] in RIDES and a[1][3] != b[1][3]:
                    self.check(bool(l[5]) and int(l[5]) >= 1, line, ">".join(l[:2]), l[5], "cross-continent transport needs a loading screen")
            directed[(l[0], l[1], l[2])].append((line, l))
            if l[6] != "1":
                directed[(l[1], l[0], l[2])].append((line, l))

        actual_ids = set()
        for line, n in nr:
            if n[1] != "taxi":
                continue
            tid = int(n[11])
            self.check(n[0] == f"TAXI_{tid}" and tid not in actual_ids, line, n[0], n[11], "client TaxiNodes.ID must uniquely match node ID, never CharacterBitNumber or slotIndex")
            actual_ids.add(tid)
            r = taxis.get(tid)
            self.check(r is not None, line, n[0], tid, "not in client TaxiNodes.csv")
            if not r:
                continue
            self.check(int(r["MountCreatureID_0"]) or int(r["MountCreatureID_1"]) or n[13] == "0", line, n[0],
                       (r["MountCreatureID_0"], r["MountCreatureID_1"]), "no flight mount; transport/marker row cannot be a flight master")
            if tid in (62, 63):
                self.check(n[13] == "0", line, n[0], n[13], "Nighthaven dialog source cannot be registered on a taxi map")
            self.check(n[12] == faction(r), line, n[0], n[12], f"client flags/mounts require faction {faction(r)!r}")
            self.check(int(n[3]) == int(r["ContinentID"]), line, n[0], n[3], f"client continent is {r['ContinentID']}")
            for col, key in ((4, "Pos_0"), (5, "Pos_1")):
                self.check(abs(float(n[col]) - float(r[key])) <= .051, line, n[0], n[col], f"client {key}={r[key]} (0.1-yard output rounding)")
            m = int(n[6])
            self.check(m in assign, line, n[0], m, "map has no full client rectangle")
            if m not in assign:
                continue
            self.check(int(assign[m]["MapID"]) == int(n[3]), line, n[0], m, "map rectangle belongs to another continent")
            x, y = project(m, float(r["Pos_0"]), float(r["Pos_1"]))
            self.check(0 <= x <= 100 and 0 <= y <= 100, line, n[0], (x, y), "client position outside chosen map")
            self.check(abs(float(n[7]) - x) <= .0051 and abs(float(n[8]) - y) <= .0051,
                       line, n[0], n[7:9], f"client projection is ({x:.4f}, {y:.4f})")
            zone = r["Name_lang"].split(", ", 1)[-1]
            expected_map = CITY_MAPS.get(tid, maps_by_name.get(normalized(zone)))
            if expected_map is None:
                # The client calls Hillsbrad Foothills "Hillsbrad", Arathi
                # Highlands "Arathi", etc. Accept only a unique zone prefix.
                candidates = [i for name, i in maps_by_name.items()
                              if name.startswith(normalized(zone))]
                if len(candidates) == 1:
                    expected_map = candidates[0]
            self.check(expected_map is not None and expected_map == m, line, n[0], m,
                       f"client name {r['Name_lang']!r} resolves to map {expected_map}; overlapping rectangles are not zone ownership")
            expected_area = next((int(rg[1]) for _, rg in regions
                                  if int(rg[0]) == m and math.hypot(x-float(rg[2]), y-float(rg[3])) <= float(rg[4])), None)
            if expected_area is not None:
                self.check(int(n[2]) == expected_area, line, n[0], self.areas[int(n[2])-1],
                           f"position is in authored routing region {self.areas[expected_area-1]}; wrong area bypasses island/cliff crossings")
            self.check(n[9] == (str(m) if m in CITY_MAPS.values() else ""), line, n[0], n[9], "taxi must respect capital city boundary")

        expected = {}
        exclusions = collections.Counter()
        for r in paths:
            a, b = int(r["FromTaxiNode"]), int(r["ToTaxiNode"])
            na, nb = taxis.get(a), taxis.get(b)
            if not na or not nb or SKIP.match(na["Name_lang"]) or SKIP.match(nb["Name_lang"]):
                exclusions["placeholder/quest/transport"] += 1
                continue
            if {a, b} & TOWERS:
                exclusions["ownership-controlled tower"] += 1
                continue
            if not all(int(n["MountCreatureID_0"]) or int(n["MountCreatureID_1"]) for n in (na, nb)):
                exclusions["no flight mount"] += 1
                continue
            if na["ContinentID"] != nb["ContinentID"] or int(na["ContinentID"]) not in (0, 1):
                exclusions["other continent"] += 1
                continue
            pts = sorted(pointsets[int(r["ID"])], key=lambda p: int(p["NodeIndex"]))
            if len(pts) < 2 or any(int(p["Delay"]) > 0 or int(p["Flags"]) & 1 for p in pts):
                exclusions["delay/transition/not enough points"] += 1
                continue
            if faction(na) and faction(nb) and faction(na) != faction(nb):
                exclusions["hostile faction"] += 1
                continue
            key = (f"TAXI_{a}", f"TAXI_{b}", "taxi")
            line = self.nodes.get(key[0], (1,))[0]
            self.check([int(p["NodeIndex"]) for p in pts] == list(range(len(pts))), line, f"TaxiPath {r['ID']}", "point indexes", "client flight points must be contiguous and unique")
            self.check(all(int(p["ContinentID"]) == int(na["ContinentID"]) for p in pts), line,
                       f"TaxiPath {r['ID']}", "point continents", "flight spline changes continent")
            for n, p, end in ((na, pts[0], "start"), (nb, pts[-1], "end")):
                gap = math.sqrt(sum((float(n[f"Pos_{i}"])-float(p[f"Loc_{i}"]))**2 for i in range(3)))
                self.check(gap <= 250, line, f"TaxiPath {r['ID']} {end}", round(gap, 1), "flight spline endpoint >250 yards from advertised flight master")
            length = sum(math.sqrt(sum((float(p[f"Loc_{i}"])-float(q[f"Loc_{i}"]))**2 for i in range(3))) for p, q in zip(pts, pts[1:]))
            if (a, b) in SPECIAL:
                exclusions["dialog flight (checked separately)"] += 1
                continue
            expected[key] = r
            options = directed.get(key, [])
            self.check(bool(options), line, f"TaxiPath {r['ID']}", key, "client flight connection missing from shipped network")
            for lline, l in options:
                self.check(float(l[3]) == round(length/30), lline, f"TaxiPath {r['ID']} {'>'.join(key[:2])}", l[3], f"declared 30 yd/s polyline estimate is {round(length/30)}s; this is not an in-game measurement")
                self.check(l[7] == (faction(na) or faction(nb)), lline, ">".join(key[:2]), l[7], "client endpoint faction not preserved on flight link")
        expected_ids = {int(k[i][5:]) for k in expected for i in (0, 1)}
        for tid in sorted(expected_ids - actual_ids):
            self.check(False, 1, f"TAXI_{tid}", "absent", f"client-connected flight master missing: {taxis[tid]['Name_lang']}")
        for line, l in lr:
            if l[2] != "taxi":
                continue
            pair = tuple(int(x[5:]) for x in l[:2])
            if pair in SPECIAL:
                fac, cls, seconds = SPECIAL[pair]
                self.check(l[7] == fac and l[8] == cls and l[6] == "1", line, ">".join(l[:2]),
                           (l[7], l[8], l[6]), "Nighthaven dialog flight must be faction-locked, DRUID-only, one-way (mz_edges.tsv)")
                self.check(l[11] == "1", line, ">".join(l[:2]), l[11], "Nighthaven service must explicitly use NPC dialog, not normal taxi-map discovery/boarding")
                if l[8] == cls:
                    self.check(float(l[3]) == seconds, line, ">".join(l[:2]), l[3], f"curated special-flight estimate is {seconds}s")
                continue
            key = (l[0], l[1], "taxi")
            self.check(key in expected, line, ">".join(l[:2]), l[3], "no eligible directed client flight path; discard transport rows and unverified legacy placeholder links")
            if l[6] != "1":
                self.check((l[1], l[0], "taxi") in expected, line, ">".join(l[:2]), "implicit reverse", "no independently supported reverse client flight")
        for (a, b, method), options in sorted(directed.items()):
            if method == "taxi":
                self.check(len(options) == 1, options[0][0], f"{a}>{b}", [line for line, _ in options], "duplicate directed flight can weaken restrictions or select a conflicting estimate")

        # Every raw transport endpoint and ride must survive extraction, including
        # move/area overrides. This establishes fidelity, not physical accuracy.
        raw_nodes = {r[0]: r for _, r in self.tsv(self.cache / "mz_nodes.tsv")}
        verification = json.loads((ROOT / 'tools/fixtures/travel/verified-routing.json').read_text())
        corrections = {r['id']: r['values'] for r in verification['transport'] if r['verdict'] == 'CORRECTED'}
        moves, homes, drops = {}, {}, set()
        for _, r in self.tsv(self.extra):
            if r[0] == "move": moves[r[1]] = (int(r[2]), float(r[3]), float(r[4]))
            elif r[0] == "area": homes[r[1]] = r[2]
            elif r[0] == "drop": drops.add(r[1])
        transport_count = 0
        for nid, r in sorted(raw_nodes.items()):
            if r[1] not in TRANSPORT or nid in drops:
                continue
            transport_count += 1
            actual = self.nodes.get(nid)
            self.check(actual is not None, 1, nid, "absent" if not actual else "present", "raw transport endpoint missing")
            if not actual: continue
            line, n = actual
            m, x, y = moves.get(nid, (int(r[3]), float(r[4])*100, float(r[5])*100))
            self.check(n[1] == r[1] and int(n[6]) == m and abs(float(n[7])-x) <= .0051 and abs(float(n[8])-y) <= .0051,
                       line, nid, n[6:9], f"source/override endpoint is map {m}, {x:.2f},{y:.2f}")
            self.check(self.areas[int(n[2])-1] == homes.get(nid, r[2]), line, nid, self.areas[int(n[2])-1], "transport area differs from raw source/area override")
            if m in assign:
                px, py = project(m, float(n[4]), float(n[5]))
                span = max(abs(float(assign[m]["Region_4"])-float(assign[m]["Region_1"])), abs(float(assign[m]["Region_3"])-float(assign[m]["Region_0"])))
                tolerance = .0051 + 5.1/span
                self.check(int(n[3]) == int(assign[m]["MapID"]) and abs(px-x) <= tolerance and abs(py-y) <= tolerance,
                           line, nid, n[3:6], "world position/continent disagrees with client map transform")
        for rawline, r in self.tsv(self.cache / "mz_edges.tsv"):
            if r[2] not in RIDES or r[0] in drops or r[1] in drops:
                continue
            correction = corrections.get(r[0] + '->' + r[1], {})
            if 'hard_faction_gate' in correction and correction['hard_faction_gate'] is None:
                r[7] = ''
            if correction.get('oneway'):
                r[6] = '1'
            if correction.get('conditional_cost_seconds'):
                r[3] = str(correction['conditional_cost_seconds'])
            if r[2] == 'tram':
                r[4] = '58.633'
            options = directed.get((r[0], r[1], r[2]), [])
            self.check(len(options) == 1, options[0][0] if options else 1, ">".join(r[:2]), len(options), f"expected one raw transport link (mz_edges.tsv:{rawline})")
            for line, l in options:
                for col in (3, 4, 6, 7, 8, 9, 10):
                    self.check(l[col] == r[col], line, ">".join(r[:2]), l[col], f"column {col+1} differs from mz_edges.tsv:{rawline} value {r[col]!r}")
                screens = r[5] or ("1" if self.nodes[r[0]][1][3] != self.nodes[r[1]][1][3] else "")
                self.check(l[5] == screens, line, ">".join(r[:2]), l[5], f"loading screens expected {screens!r}")

        teleport_rows = self.block("teleports", 3)
        actual_teleports = {int(r[0]): (line, r) for line, r in teleport_rows}
        source_teleports = {int(r[1]): r for _, r in self.tsv(self.cache / "mz_misc.tsv")
                            if r[0] == "teleport" and r[2] in self.nodes}
        self.check(len(actual_teleports) == len(teleport_rows), 1, "teleports", len(teleport_rows), "duplicate teleport spell IDs")
        self.check(set(actual_teleports) == set(source_teleports), 1, "teleports", sorted(actual_teleports), "teleport spell set differs from raw abilities dump")
        for spell, (line, r) in sorted(actual_teleports.items()):
            source = source_teleports.get(spell)
            self.check(r[1] in self.nodes, line, f"teleport {spell}", r[1], "teleport landing endpoint missing")
            self.check(bool(source) and r[1] == source[2] and float(r[2]) == float(source[3]),
                       line, f"teleport {spell}", r[1:], "landing endpoint/cast duration differs from mz_misc.tsv")

        for fac in ("Alliance", "Horde"):
            for cont in (0, 1):
                ids = {tid for tid in expected_ids if int(taxis[tid]["ContinentID"]) == cont and faction(taxis[tid]) in ("", fac)}
                adjacency = collections.defaultdict(set)
                for a, b, _ in expected:
                    ai, bi = int(a[5:]), int(b[5:])
                    if ai in ids and bi in ids: adjacency[ai].add(bi)
                components = []
                for start in sorted(ids):
                    seen, stack = set(), [start]
                    while stack:
                        current = stack.pop()
                        if current not in seen:
                            seen.add(current); stack.extend(sorted(adjacency[current]-seen))
                    if seen not in components: components.append(seen)
                print(f"INFO normal taxi reachability {fac} continent={cont}: {len(ids)} nodes, {len(components)} distinct reachable sets")
                if len(components) > 1:
                    self.warn(f"{fac}/{cont}", f"client-only disconnected components: {[sorted(x) for x in components]}; do not invent links")
        for tid, r in sorted(taxis.items()):
            if SKIP.match(r["Name_lang"]) or int(r["ContinentID"]) not in (0, 1) or tid in TOWERS or tid in actual_ids:
                continue
            if int(r["CharacterBitNumber"]) and (int(r["MountCreatureID_0"]) or int(r["MountCreatureID_1"])):
                self.warn(f"TaxiNodes.csv ID={tid}", f"{r['Name_lang']}: omitted; {sum(tid in (int(p['FromTaxiNode']), int(p['ToTaxiNode'])) for p in paths)} client paths; active service needs in-game evidence")
        fare_rows = self.block("taxiFares", 3)
        shipped_fares = {}
        for line, f in fare_rows:
            key = (f[0], f[1], "taxi")
            self.check(key not in shipped_fares, line, ">".join(f[:2]), f[2], "duplicate directional fare")
            shipped_fares[key] = f[2]
        for key, r in expected.items():
            self.check(shipped_fares.get(key) == r["Cost"], 1, ">".join(key[:2]), shipped_fares.get(key),
                       "base copper fare must preserve TaxiPath.Cost=" + r["Cost"])
        for key, fare in shipped_fares.items():
            self.check(any(("TAXI_" + r["FromTaxiNode"], "TAXI_" + r["ToTaxiNode"], "taxi") == key
                           and r["Cost"] == fare for r in paths), 1, ">".join(key[:2]), fare,
                       "fare lacks matching client TaxiPath source")
        self.warn("flight durations", "all ordinary times are rounded polyline length / 30 yd/s; physical spline, acceleration and beta perks are unmeasured")
        self.warn("dialog flight discovery", "62/63 have CharacterBitNumber=0; preserve dialog availability independently of taxi-map discovery; runtime validator verifies this")
        self.warn("conditional towers", "84/85/86/87 and their client paths excluded; require live ownership gating before inclusion")
        if self.tickets:
            samples = {(int(a), int(b), fac): int(t) for a, b, t, fac in re.findall(
                r'from = "TAXI_(\d+)", to = "TAXI_(\d+)", method = "flight", cost = (\d+), requirements = \{ faction = "(\w+)"',
                self.tickets.read_text())}
            if not samples:
                raise ValueError(f"{self.tickets}: no InFlight ticket rows parsed")
            errors = []
            for key in sorted(expected):
                a, b = (int(key[i][5:]) for i in (0, 1))
                for line, l in directed.get(key, []):
                    t = samples.get((a, b, l[7]))
                    if t is None: continue
                    relative = abs(float(l[3])/t - 1)
                    errors.append(relative)
                    self.check(relative <= .10, line, f"{key[0]}>{key[1]}", l[3],
                               f"independent Classic InFlight direct-leg ticket is {t}s; >10% drift needs build-specific review")
                    if relative >= .025:
                        self.warn(f"{self.label(self.data)}:{line} {key[0]}>{key[1]}",
                                  f"{l[3]}s estimate vs {t}s Classic InFlight ({relative:.1%}); beta correctness needs live timing")
            print(f"INFO independent InFlight: {len(samples)} tickets; {len(errors)} matched direct legs; "
                  f"median absolute error={statistics.median(errors):.2%}; "
                  f"within 1%={sum(e <= .01 for e in errors)}, 5%={sum(e <= .05 for e in errors)}, 10%={sum(e <= .10 for e in errors)}")
        else:
            print("INFO optional timing cross-check: pass --tickets <Mapzeroth/tools/flight_source/inflight_tickets.lua>")
        print(f"INFO inputs: {len(taxis)} client taxi rows, {len(paths)} paths; exclusions={dict(sorted(exclusions.items()))}")
        print(f"INFO scope: {len(actual_ids)} shipped taxi nodes, {len(expected)} ordinary client flight paths, {transport_count} raw transport endpoints, {sum(l[2] in RIDES for _, l in lr)} transport link rows, {len(actual_teleports)} teleport abilities")
        print(f"RESULT {self.checks} checks, {self.errors} failures, {self.warnings} warnings")
        return 1 if self.errors else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=ROOT / "WaypointTracker/TravelData.lua")
    parser.add_argument("--cache", type=Path, default=ROOT / "tools/fixtures/travel")
    parser.add_argument("--extra", type=Path, default=ROOT / "tools/travel_extra.tsv")
    parser.add_argument("--tickets", type=Path, help="optional independent Classic InFlight direct-leg reference")
    args = parser.parse_args()
    try:
        return Audit(args.data, args.cache, args.extra, args.tickets).run()
    except (OSError, ValueError, KeyError, IndexError, TypeError) as e:
        print(f"FAIL audit input/schema: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
