#!/usr/bin/env python3
"""Builds WaypointTracker_Data/Client.lua from the WoW Forever game client's
own data tables (DB2), as published by https://wago.tools.

What it takes from the client:
  * the quest IDs that only WoW Forever has (not in Classic Era or
    Anniversary), written to WaypointTracker/ForeverQuests.lua. The client
    has no quest names; the addon asks the game for them while you play.
  * quest map markers (QuestPOIBlob/QuestPOIPoint): where Forever quests
    start, where their objectives are and where they are handed in
  * every flight path (TaxiNodes), including the new Forever ones
  * town names on the world map (AreaPOI)

Usage:
  python3 tools/build_forever.py [--build 1.60.1.70205] [--cache DIR]
"""
import argparse
import re
import csv
import io
import os
import sys
import urllib.request

ERA_BUILD = "1.15.9.69722"
ANNIVERSARY_BUILD = "2.5.6.69795"
LOCALES = ["enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "zhCN", "zhTW", "koKR"]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "WaypointTracker_Data", "Client.lua")
QUESTS_OUT = os.path.join(HERE, "..", "WaypointTracker", "ForeverQuests.lua")
DATA_LUA = os.path.join(HERE, "..", "WaypointTracker_Data", "Data.lua")
ITEMS_OUT = os.path.join(HERE, "..", "WaypointTracker_Data", "Items.lua")
ITEM_NAMES_OUT = os.path.join(HERE, "..", "WaypointTracker_Data", "Items_{}.lua")



def lua_long(body, level=0):
    """body as a Lua long string, with a bracket level the text can't close."""
    while "]" + "=" * level + "]" in body:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{body}\n]{eq}]"

def fetch(table, build, cache, locale=None):
    name = f"{table}-{build}-{locale or 'enUS'}.csv"
    path = os.path.join(cache, name)
    if not os.path.exists(path):
        url = f"https://wago.tools/db2/{table}/csv?build={build}"
        if locale and locale != "enUS":
            url += f"&locale={locale}"
        print("downloading", url, file=sys.stderr)
        req = urllib.request.Request(url, headers={"User-Agent": "WaypointTracker-build/1.0 (+https://github.com/sanjaygbhat/wowforever-waypoint-tracker)"})
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def clean(s):
    return (s or "").replace("\t", " ").replace("\n", " ").replace("]]", "] ]").strip()


def num(s):
    return float(s or 0)


def shipped_ids(block):
    """IDs in the classic database built from pfQuest (Data.lua)."""
    with open(DATA_LUA, encoding="utf-8") as f:
        src = f.read()
    m = re.search(block + r" = \[==\[\n(.*?)\]==\]", src, re.S)
    return {int(l.split("\t")[0]) for l in m.group(1).splitlines() if l.strip()}


def curated_quest_ids():
    """Quest IDs in the curated database (Curated.lua, from tools/build_att.lua)."""
    path = os.path.join(HERE, "..", "WaypointTracker_Data", "Curated.lua")
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        return {int(m) for m in re.findall(r"^Q\t(\d+)\t", f.read(), re.M)}


def pfquest_item_ids(path):
    """Every item pfQuest knows (not only the quest items shipped)."""
    with open(os.path.join(path, "db", "enUS", "items.lua"), encoding="utf-8", errors="replace") as f:
        return {int(x) for x in re.findall(r"\[(\d+)\]\s*=", f.read())}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default="1.60.1.70205")
    ap.add_argument("--cache", default=os.path.join(HERE, ".cache"))
    ap.add_argument("--classic", "--pfquest", dest="classic", default=os.environ.get("PFQUEST", ""),
                    help="checkout of the classic database source; items it knows are left to it")
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)
    b = args.build

    # quests the Forever client has that the classic database (pfQuest)
    # doesn't: WoW Forever's own, plus Season of Discovery ones Forever kept
    forever = {int(r["ID"]) for r in fetch("QuestV2", b, args.cache)}
    shipped_quests = shipped_ids("quests")
    # and the curated database's quests the classic one doesn't have (some
    # aren't in the client's table), so the game is asked for their names too
    only = sorted((forever | curated_quest_ids()) - shipped_quests)

    # zones, to know which zone a world position is in
    uimaps = {int(r["ID"]): r for r in fetch("UiMap", b, args.cache)}
    assign = []
    for r in fetch("UiMapAssignment", b, args.cache):
        m = uimaps.get(int(r["UiMapID"]))
        if not m or m["Type"] != "3":  # zones only
            continue
        x0, y0, x1, y1 = num(r["Region_0"]), num(r["Region_1"]), num(r["Region_3"]), num(r["Region_4"])
        assign.append((int(r["MapID"]), min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), int(r["UiMapID"])))

    def zone_of(cont, x, y):
        best, area = 0, None
        for mid, x0, y0, x1, y1, ui in assign:
            if mid == cont and x0 <= x <= x1 and y0 <= y <= y1:
                a = (x1 - x0) * (y1 - y0)
                if area is None or a < area:
                    best, area = ui, a
        return best

    # quest markers: -1 = hand in, 32 = start, 0..31 = objectives
    blobs = {int(r["ID"]): r for r in fetch("QuestPOIBlob", b, args.cache)}
    pts = {}
    for r in fetch("QuestPOIPoint", b, args.cache):
        pts.setdefault(int(r["QuestPOIBlobID"]), []).append((num(r["X"]), num(r["Y"])))
    poi_lines, seen = [], set()
    for bid in sorted(blobs):
        r = blobs[bid]
        p = pts.get(bid)
        if not p or r["Flags"] not in ("0", ""):
            continue
        idx = int(r["ObjectiveIndex"])
        kind = "end" if idx == -1 else "start" if idx == 32 else ("obj%d" % idx) if 0 <= idx < 32 else None
        if not kind:
            continue
        x = sum(q[0] for q in p) / len(p)
        y = sum(q[1] for q in p) / len(p)
        key = (r["QuestID"], kind, round(x), round(y))
        if key in seen:
            continue
        seen.add(key)
        poi_lines.append(f"{r['QuestID']}\t{kind}\t{r['MapID']}\t{r['UiMapID']}\t{x:.1f}\t{y:.1f}")

    # flight paths
    taxi = fetch("TaxiNodes", b, args.cache)
    flight_lines, flight_ids = [], set()
    for r in taxi:
        name = r["Name_lang"]
        if not name or name.startswith("Quest Path") or name.startswith("zz") or r["ContinentID"] not in ("0", "1"):
            continue
        flags = int(r["Flags"] or 0)
        fac = ("A" if flags & 1 else "") + ("H" if flags & 2 else "")
        x, y, cont = num(r["Pos_0"]), num(r["Pos_1"]), int(r["ContinentID"])
        ui = zone_of(cont, x, y)
        if not ui:  # test and GM islands
            continue
        flight_ids.add(r["ID"])
        flight_lines.append(f"{r['ID']}\t{cont}\t{ui}\t{x:.1f}\t{y:.1f}\t{fac}")

    # towns on the world map
    town_lines, town_ids = [], set()
    for r in fetch("AreaPOI", b, args.cache):
        if not r["Name_lang"] or r["Icon"] not in ("4", "5", "6") or r["ContinentID"] not in ("0", "1"):
            continue
        x, y, cont = num(r["Pos_0"]), num(r["Pos_1"]), int(r["ContinentID"])
        ui = zone_of(cont, x, y)
        if not ui:
            continue
        town_ids.add(r["ID"])
        town_lines.append(f"{r['ID']}\t{cont}\t{ui}\t{x:.1f}\t{y:.1f}")

    # names in every language
    names = {}
    for loc in LOCALES:
        fl = [f"{r['ID']}\t{clean(r['Name_lang'])}" for r in fetch("TaxiNodes", b, args.cache, loc) if r["ID"] in flight_ids]
        tl = [f"{r['ID']}\t{clean(r['Name_lang'])}" for r in fetch("AreaPOI", b, args.cache, loc) if r["ID"] in town_ids]
        names[loc] = (fl, tl)

    out = io.StringIO()
    w = out.write
    w("-- Generated by tools/build_forever.py from the WoW Forever game client's own\n")
    w(f"-- data tables (build {b}, via wago.tools). Do not edit.\n")
    w("local D = WaypointTrackerData\n")
    w("if not D then\n    return\nend\n")
    w("D.client = {\n")
    w(f'    build = "{b}",\n')
    w("    -- quest markers: quest, start/end/objN, continent, zone, world x, world y\n")
    w("    pois = " + lua_long("\n".join(poi_lines)) + ",\n")
    w("    -- flight paths: id, continent, zone, world x, world y, faction\n")
    w("    flights = " + lua_long("\n".join(flight_lines)) + ",\n")
    w("    -- towns: id, continent, zone, world x, world y\n")
    w("    towns = " + lua_long("\n".join(town_lines)) + ",\n")
    w("}\n")
    w("local names = {\n")
    for loc in LOCALES:
        fl, tl = names[loc]
        w(f"    {loc} = {{\n        flights = " + lua_long("\n".join(fl)) + ",\n        towns = " + lua_long("\n".join(tl)) + ",\n    },\n")
    w("}\n")
    w("local locale = GetLocale and GetLocale() or \"enUS\"\n")
    w("D.client.names = names[locale] or names.enUS\n")
    w("D.client.fallbackNames = names.enUS\n")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(out.getvalue())
    # the quest list is small and needed from login, so it lives in the addon
    with open(QUESTS_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/build_forever.py from the WoW Forever game client's\n")
        f.write(f"-- quest table (build {b}): quests the classic database lacks.\n")
        f.write("-- The client has no names for them, so Learn.lua asks the game. Do not edit.\n")
        f.write("local _, ns = ...\n")
        f.write('ns.foreverQuests = "' + ",".join(map(str, only)) + '"\n')
    n_items = build_items(b, args, shipped_ids("items"))
    print(f"{n_items} items, {len(only)} quests without classic data, {len(poi_lines)} quest markers, "
          f"{len(flight_lines)} flight paths, {len(town_lines)} towns -> {os.path.relpath(OUT)}")


def build_items(b, args, shipped):
    """Items from the Forever client: what the classic database lacks (all of
    it), plus details for the quest items it already has."""
    sparse = {int(r["ID"]): r for r in fetch("ItemSparse", b, args.cache)}
    classes = {int(r["ID"]): r for r in fetch("Item", b, args.cache)}
    known = pfquest_item_ids(args.classic) if args.classic else set(shipped)
    new = {i for i in sparse if i not in known}
    keep = sorted(new | (shipped & set(sparse)))
    lines = []
    for i in keep:
        r, c = sparse[i], classes.get(i, {})
        lines.append("\t".join([
            str(i), c.get("ClassID", ""), c.get("SubclassID", ""), r["OverallQualityID"],
            r["ItemLevel"], r["RequiredLevel"], r["StartQuestID"] if r["StartQuestID"] != "0" else "",
            "1" if i in new else "",
        ]))
    with open(ITEMS_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/build_forever.py from the WoW Forever game client's\n")
        f.write(f"-- item tables (build {b}, via wago.tools). Do not edit.\n")
        f.write("local D = WaypointTrackerData\nif not D then\n    return\nend\n")
        f.write("-- id, class, subclass, quality, item level, required level, starts quest,\n")
        f.write("-- 1 when the classic database doesn't have it\n")
        f.write("D.clientItems = " + lua_long("\n".join(lines)) + "\n")
    for loc in LOCALES:
        rows = sparse if loc == "enUS" else {int(r["ID"]): r for r in fetch("ItemSparse", b, args.cache, loc)}
        out = []
        for i in keep:
            r = rows.get(i)
            if not r:
                continue
            name = clean(r["Display_lang"]) if i in new else ""
            desc = clean(r["Description_lang"])
            if name or desc:
                out.append(f"{i}\t{name}\t{desc}")
        with open(ITEM_NAMES_OUT.format(loc), "w", encoding="utf-8", newline="\n") as f:
            f.write("-- Generated by tools/build_forever.py from the WoW Forever game client's\n")
            f.write(f"-- item names ({loc}, build {b}). Do not edit.\n")
            if loc != "enUS":
                f.write(f'if GetLocale() ~= "{loc}" then\n    return\nend\n')
            f.write("local D = WaypointTrackerData\nif not D then\n    return\nend\n")
            f.write("D.clientItemNames = D.clientItemNames or {}\n")
            f.write("-- id, name (only for items the classic database lacks), description\n")
            f.write(f"D.clientItemNames.{loc} = " + lua_long("\n".join(out), 2) + "\n")
    return len(keep)


if __name__ == "__main__":
    main()
