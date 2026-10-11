#!/usr/bin/env python3
"""Builds WaypointTracker/TravelData.lua: the travel network Real routes plans on.

Inputs (in tools/.cache/travel/, not checked in):
  * the WoW Forever client's own tables, from wago.tools (build 1.60.1.x):
    TaxiNodes, TaxiPath, TaxiPathNode, UiMapAssignment, UiMap, AreaTable
        curl -o TaxiNodes.csv "https://wago.tools/db2/TaxiNodes/csv?build=1.60.1.70338"
  * Mapzeroth's Forever data (MIT, github.com/tr0tsky0/Mapzeroth, branch
    "rebuild", Data/Forever), dumped to mz_*.tsv by tools/mapzeroth_dump.lua:
    zone crossings, city gates, docks, zeppelin towers, the tram, portals,
    inns, the ships and zeppelins with their measured times.
  * tools/travel_extra.tsv (ours): more crossings, passes, sub-areas, zone
    levels and corrections on top of Mapzeroth's.

Flights come from the client: every flight path between two flight masters,
timed by the length of its flight line at 30 yards a second (this matches
InFlight's measured times to about 1%).

usage: tools/build_travel.py [cache dir] [output file]
"""
import csv
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, ".cache", "travel")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "WaypointTracker", "TravelData.lua")
EXTRA = os.environ.get("TRAVEL_EXTRA") or os.path.join(HERE, "travel_extra.tsv")

FLIGHT_SPEED = 30.0  # yards a second on a flight path
# Mapzeroth node kinds Real routes uses (the rest are things to go to, not ways to travel)
KEEP_KINDS = {"border", "dock", "zeppelin", "tram", "portal", "entrance", "inn", "teleport", "settlement", "pass"}
METHODS = {"walk", "gate", "taxi", "ship", "zeppelin", "tram", "portal", "transition", "lift"}


def read_csv(name):
    with open(os.path.join(CACHE, name), encoding="utf-8") as f:
        return list(csv.DictReader(f))


def read_tsv(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line and not line.startswith("#"):
                rows.append(line.split("\t"))
    return rows


def num(s):
    return float(s) if s not in ("", None) else None


# --- maps: uiMap <-> world --------------------------------------------------
uimaps = {int(r["ID"]): r for r in read_csv("UiMap.csv")}
assign = {}
for r in read_csv("UiMapAssignment.csv"):
    m = int(r["UiMapID"])
    if m in assign or [float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")] != [0, 0, 1, 1]:
        continue
    assign[m] = {
        "cont": int(r["MapID"]),
        "minX": float(r["Region_0"]), "minY": float(r["Region_1"]), "minZ": float(r["Region_2"]),
        "maxX": float(r["Region_3"]), "maxY": float(r["Region_4"]), "maxZ": float(r["Region_5"]),
    }


def to_world(m, x, y):
    a = assign.get(m)
    if not a:
        return None
    return a["cont"], a["maxX"] - y * (a["maxX"] - a["minX"]), a["maxY"] - x * (a["maxY"] - a["minY"])


def to_map(m, wx, wy):
    a = assign[m]
    return (a["maxY"] - wy) / (a["maxY"] - a["minY"]), (a["maxX"] - wx) / (a["maxX"] - a["minX"])


def zone_of(cont, wx, wy, wz=None):
    """The smallest zone or city map holding a world position (with its
    height, when known: Undercity's map is only the ground below the ruins)."""
    best, size = None, None
    for m, a in assign.items():
        t = int(uimaps.get(m, {}).get("Type", 0) or 0)
        if a["cont"] != cont or t not in (3, 4):  # zone (3) or a city/dungeon map drawn as one
            continue
        if wz is not None and not (a["minZ"] <= wz <= a["maxZ"]):
            continue
        if a["minX"] <= wx <= a["maxX"] and a["minY"] <= wy <= a["maxY"]:
            s = (a["maxX"] - a["minX"]) * (a["maxY"] - a["minY"])
            if size is None or s < size:
                best, size = m, s
    return best


# --- area names (for docks and towns, so the game can name them in any language)
areas_by_name = {}
for r in read_csv("AreaTable.csv"):
    key = re.sub(r"[^a-z]", "", r["AreaName_lang"].lower())
    areas_by_name.setdefault(key, int(r["ID"]))


def area_id(name):
    return areas_by_name.get(re.sub(r"[^a-z]", "", name.lower()))


# --- Mapzeroth's data -------------------------------------------------------
mz_nodes = {}
for f in read_tsv(os.path.join(CACHE, "mz_nodes.tsv")):
    nid, kind, container, m, x, y, city, town, fac, area, npc = f[:11]
    mz_nodes[nid] = dict(id=nid, kind=kind, container=container, map=int(m), x=float(x), y=float(y),
                         city=city, town=town, fac=fac, area=area, npc=npc)
mz_edges = read_tsv(os.path.join(CACHE, "mz_edges.tsv"))
settlements = {}
for f in read_tsv(os.path.join(CACHE, "mz_settlements.tsv")):
    kind, key, m, x, y, taxi, fac, area = (f + [""] * 8)[:8]
    settlements[key] = dict(kind=kind, key=key, map=int(m), x=float(x), y=float(y), fac=fac,
                            area=int(area) if area else area_id(key.replace("_", " ")))
factors, indoor, teleports = {}, set(), []
for f in read_tsv(os.path.join(CACHE, "mz_misc.tsv")):
    if f[0] == "factor":
        factors[int(f[1])] = float(f[2])
    elif f[0] == "container" and len(f) > 2 and f[2] == "indoor":
        indoor.add(f[1])
    elif f[0] == "teleport":
        teleports.append((int(f[1]), f[2], float(f[3])))

# ours: extra nodes, links, sub-areas, zone levels, fixes
extra_nodes, extra_links, regions, levels, drops, moves, rehome = [], [], [], {}, set(), {}, {}
if os.path.exists(EXTRA):
    for f in read_tsv(EXTRA):
        kind = f[0]
        if kind == "node":  # node id kind container map x y [note]
            extra_nodes.append(dict(id=f[1], kind=f[2], container=f[3], map=int(f[4]), x=float(f[5]) / 100,
                                    y=float(f[6]) / 100, city="", town="", fac="", area="", npc=""))
        elif kind == "link":  # link from to method cost [oneway] [faction] [seconds aboard] [loading screens]
            extra_links.append(f[1:])
        elif kind == "region":  # region map container x y radius (percent)
            regions.append((int(f[1]), f[2], float(f[3]) / 100, float(f[4]) / 100, float(f[5]) / 100))
        elif kind == "level":  # level map min max
            levels[int(f[1])] = (int(f[2]), int(f[3]))
        elif kind == "drop":  # drop node-id
            drops.add(f[1])
        elif kind == "area":  # area node-id area: one of Mapzeroth's nodes is in a sub-area
            rehome[f[1]] = f[2]
        elif kind == "move":  # move node-id map x y: a better position for one of Mapzeroth's
            moves[f[1]] = (int(f[2]), float(f[3]) / 100, float(f[4]) / 100)

for nid, (m, x, y) in moves.items():
    if nid in mz_nodes:
        mz_nodes[nid].update(map=m, x=x, y=y)
for nid, area in rehome.items():
    if nid in mz_nodes:
        mz_nodes[nid]["container"] = area
nodes = {}
for n in list(mz_nodes.values()) + extra_nodes:
    if n["kind"] not in KEEP_KINDS or n["id"] in drops:
        continue
    if n["kind"] == "settlement" and not n["id"].startswith("CITY_"):
        continue
    w = to_world(n["map"], n["x"], n["y"])
    if not w:
        print("no world position for", n["id"], n["map"], file=sys.stderr)
        continue
    n["cont"], n["wx"], n["wy"] = w
    nodes[n["id"]] = n

# which container most of a map's nodes are in (a position on that map is in it)
map_votes = {}
for n in list(mz_nodes.values()) + extra_nodes:
    if n["container"]:
        map_votes.setdefault(n["map"], {}).setdefault(n["container"], 0)
        map_votes[n["map"]][n["container"]] += 1
map_area = {m: max(v.items(), key=lambda kv: kv[1])[0] for m, v in map_votes.items()}

# --- flights from the client ------------------------------------------------
taxi = {int(r["ID"]): r for r in read_csv("TaxiNodes.csv")}
path_points = {}
for r in read_csv("TaxiPathNode.csv"):
    path_points.setdefault(int(r["PathID"]), []).append(r)
# Eastern Plaguelands' towers only fly between each other, for whoever holds them
PVP_TOWERS = {84, 85, 86, 87}
SKIP = re.compile(r"^(Transport|Generic|Quest Path|zzOLD|Programmer|Naxxramas)", re.I)


def faction_of(r):
    h, a = int(r["MountCreatureID_0"] or 0), int(r["MountCreatureID_1"] or 0)
    flags = int(r["Flags"] or 0)
    if flags & 3 == 3 or (h and a):
        return ""
    if flags & 1 or (a and not h):
        return "A"
    if flags & 2 or (h and not a):
        return "H"
    return ""


flights = []
used = set()
for r in read_csv("TaxiPath.csv"):
    a, b = int(r["FromTaxiNode"]), int(r["ToTaxiNode"])
    na, nb = taxi.get(a), taxi.get(b)
    if not na or not nb or SKIP.match(na["Name_lang"]) or SKIP.match(nb["Name_lang"]) or {a, b} & PVP_TOWERS:
        continue
    if na["ContinentID"] != nb["ContinentID"] or int(na["ContinentID"]) not in (0, 1):
        continue
    pts = sorted(path_points.get(int(r["ID"]), []), key=lambda p: int(p["NodeIndex"]))
    if len(pts) < 2 or any(int(p["Delay"] or 0) > 0 or int(p["Flags"] or 0) & 1 for p in pts):
        continue
    length = 0.0
    for p, q in zip(pts, pts[1:]):
        length += math.sqrt(sum((float(p["Loc_%d" % i]) - float(q["Loc_%d" % i])) ** 2 for i in range(3)))
    fa, fb = faction_of(na), faction_of(nb)
    fac = fa or fb
    if fa and fb and fa != fb:
        continue
    flights.append((a, b, round(length / FLIGHT_SPEED), {"A": "Alliance", "H": "Horde"}.get(fac, "")))
    used.update((a, b))

for tid in sorted(used):
    r = taxi[tid]
    cont, wx, wy, wz = int(r["ContinentID"]), float(r["Pos_0"]), float(r["Pos_1"]), float(r["Pos_2"])
    nid = "TAXI_%d" % tid
    mz = mz_nodes.get(nid)
    m = zone_of(cont, wx, wy, wz) or zone_of(cont, wx, wy) or (mz and mz["map"])
    if not m or m not in assign:
        print("flight master on no map:", tid, r["Name_lang"], file=sys.stderr)
        continue
    x, y = to_map(m, wx, wy)
    container = (mz and mz["container"]) or map_area.get(m)
    if not container:
        print("flight master with no area:", tid, r["Name_lang"], m, file=sys.stderr)
        continue
    nodes[nid] = dict(id=nid, kind="taxi", container=container, map=m, x=x, y=y, cont=cont, wx=wx, wy=wy,
                      fac=faction_of(r), taxi=tid, city="", town="", area="", npc="")
    map_area.setdefault(m, container)

# --- cities: walled, entered through their gates ----------------------------
city_maps = {s["map"]: key for key, s in settlements.items() if s["kind"] == "city" and s["map"] in uimaps
             and int(uimaps[s["map"]].get("Type", 0) or 0) == 3 and key != "dalaran"}
links = []
for key in sorted(set(city_maps.values())):
    m = [mm for mm, k in city_maps.items() if k == key][0]
    gates = [n for n in nodes.values() if n["kind"] == "entrance" and n.get("city") == key]
    inner = [n for n in gates if n["map"] == m]
    outer = [n for n in gates if n["map"] != m]
    for i in inner:
        if not outer:
            break
        o = min(outer, key=lambda o: (o["wx"] - i["wx"]) ** 2 + (o["wy"] - i["wy"]) ** 2)
        links.append([i["id"], o["id"], "gate", "0", "", "", "", "", "", "", ""])

# --- links ------------------------------------------------------------------
have_flight = {(a, b) for a, b, _, _ in flights}
for f in mz_edges:
    f = (f + [""] * 11)[:11]
    frm, to, method = f[0], f[1], f[2]
    if frm not in nodes or to not in nodes or frm in drops or to in drops:
        continue
    if method == "taxi":
        a, b = int(frm[5:]), int(to[5:])
        if not f[8] and ((a, b) in have_flight or (b, a) in have_flight):
            continue  # the client's own flight is better
    if method not in METHODS:
        f[2] = "walk"
    links.append(f)
for a, b, cost, fac in flights:
    links.append(["TAXI_%d" % a, "TAXI_%d" % b, "taxi", str(cost), "", "", "1", fac, "", "", ""])
for f in extra_links:
    f = (f + [""] * 8)[:8]
    links.append([f[0], f[1], f[2], f[3], f[6], f[7], f[4], f[5], "", "", ""])
links = [l for l in links if l[0] in nodes and l[1] in nodes]
for l in links:
    if l[2] != "taxi" and l[5] == "" and nodes[l[0]]["cont"] != nodes[l[1]]["cont"]:
        l[5] = "1"

# --- write ------------------------------------------------------------------
containers = sorted({n["container"] for n in nodes.values()} | {c for _, c, *_ in regions} | set(map_area.values()))
cidx = {c: i + 1 for i, c in enumerate(containers)}
city_of_map = {m: k for m, k in city_maps.items()}


def fmt(v, d=1):
    s = ("%." + str(d) + "f") % v
    return s.rstrip("0").rstrip(".") if "." in s else s


def label_area(n):
    """An area id the game can name a dock or tower by: the nearest town."""
    if n["kind"] not in ("dock", "zeppelin", "tram", "portal", "inn", "settlement"):
        return ""
    best, bd = None, None
    for s in settlements.values():
        w = to_world(s["map"], s["x"], s["y"])
        if not w or w[0] != n["cont"] or not s["area"]:
            continue
        d = math.hypot(w[1] - n["wx"], w[2] - n["wy"])
        if bd is None or d < bd:
            best, bd = s, d
    return str(best["area"]) if best and bd < 900 else ""


node_lines = []
for nid in sorted(nodes):
    n = nodes[nid]
    inside = n["map"] if n["map"] in city_of_map else ""
    node_lines.append("\t".join([
        nid, n["kind"], str(cidx[n["container"]]), str(n["cont"]), fmt(n["wx"]), fmt(n["wy"]),
        str(n["map"]), fmt(n["x"] * 100, 2), fmt(n["y"] * 100, 2), str(inside), label_area(n),
        str(n.get("taxi", "")), {"A": "Alliance", "H": "Horde"}.get(n["fac"], n["fac"] or ""),
    ]))
link_lines = ["\t".join(l[:11]) for l in links]
map_lines = ["%d\t%d" % (m, cidx[c]) for m, c in sorted(map_area.items()) if c in cidx]
region_lines = ["%d\t%d\t%s\t%s\t%s" % (m, cidx[c], fmt(x * 100, 2), fmt(y * 100, 2), fmt(r * 100, 2))
                for m, c, x, y, r in regions]
city_lines = ["%d\t%s" % (m, settlements[k]["fac"]) for m, k in sorted(city_maps.items())]
settle_lines = []
for key in sorted(settlements):
    s = settlements[key]
    inn = next((n["id"] for n in nodes.values() if n["kind"] == "inn" and (n["town"] == key or n["city"] == key)), "")
    if s["area"] and inn:
        settle_lines.append("%s\t%d\t%s" % (key, s["area"], inn))
tele_lines = ["%d\t%s\t%s" % (s, t, fmt(c)) for s, t, c in teleports if t in nodes]
factor_lines = ["%d\t%s" % (m, fmt(f, 2)) for m, f in sorted(factors.items())]
level_lines = ["%d\t%d\t%d" % (m, lo, hi) for m, (lo, hi) in sorted(levels.items())]
indoor_ids = sorted(cidx[c] for c in indoor if c in cidx)


def block(name, lines, comment):
    return "    -- %s\n    %s = [[\n%s\n]],\n" % (comment, name, "\n".join(lines))


with open(OUT, "w", encoding="utf-8") as out:
    out.write("-- Generated by tools/build_travel.py from the WoW Forever client's flight\n")
    out.write("-- tables and Mapzeroth's Forever travel data (MIT, see THIRD-PARTY-LICENSES.txt). Do not edit.\n")
    out.write("local _, ns = ...\n")
    out.write("ns.TravelData = {\n")
    out.write("    -- areas you can walk around in freely (a zone, or part of one)\n")
    out.write("    areas = {\n%s\n    },\n" % "\n".join('        "%s",' % c for c in containers))
    out.write("    indoor = { %s },\n" % ", ".join("[%d] = true" % i for i in indoor_ids))
    out.write(block("nodes", node_lines,
                    "id, kind, area, continent, world x, world y, map, x, y, inside city map, town area id, flight node, faction"))
    out.write(block("links", link_lines,
                    "from, to, method, seconds, seconds aboard, loading screens, one way, faction, class, race, quest"))
    out.write(block("maps", map_lines, "map, the area a position on it is in"))
    out.write(block("regions", region_lines, "map, area, x, y, radius: the part of a map that's another area"))
    out.write(block("cities", city_lines, "walled city map, faction"))
    out.write(block("towns", settle_lines, "town, area id (the hearthstone's bind name), inn node"))
    out.write(block("teleports", tele_lines, "spell, node it lands at, cast seconds"))
    out.write(block("factors", factor_lines, "map, how much longer walking is than the straight line"))
    out.write(block("levels", level_lines, "map, lowest and highest level of its creatures"))
    out.write("}\n")

kinds = {}
for n in nodes.values():
    kinds[n["kind"]] = kinds.get(n["kind"], 0) + 1
methods = {}
for l in links:
    methods[l[2]] = methods.get(l[2], 0) + 1
print("nodes", len(nodes), kinds)
print("links", len(links), methods)
print("areas", len(containers), "maps", len(map_lines), "towns", len(settle_lines), "flights", len(flights))
print("wrote", OUT, os.path.getsize(OUT), "bytes")
