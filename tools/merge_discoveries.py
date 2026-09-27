#!/usr/bin/env python3
"""Merge players' discoveries into WaypointTracker_Data/Forever.lua.

Two kinds of input, in any mix:

* Shared text (*.txt): what Find > Share discoveries gives, pasted into a
  GitHub issue. Save each one as a .txt file.
* The addon's saved file (*.lua): WTF/Account/<account>/SavedVariables/
  WaypointTracker.lua from a WoW Forever install. It holds everything that
  player's game wrote down.

    python3 tools/merge_discoveries.py shared/*.txt WaypointTracker.lua

What was seen in the game most recently wins: files given later on the
command line correct earlier ones (quest givers, hand-ins, levels,
friendly/hostile, titles). Spots are added (one per 1% square, 30 per map
at most). Names, titles and quest text are only taken from English clients,
unless nothing is known yet, so the shared file stays in one language
(--locale enUS marks a saved file as English when it can't tell).

Only what adds to the shipped database is kept: NPCs and objects it doesn't
have, or has without a name, title, service or a spot near the one seen;
drops and vendors it doesn't list. Everything read is treated as untrusted:
the saved file is parsed as data (never run), numbers are checked, and text
is stripped of the game's escape codes.
"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "WaypointTracker_Data"
TARGET = DATA / "Forever.lua"
MAX_SPOTS = 30
MAX_MAPS = 20
MAX_SELLERS = 20
MAX_DROPS = 40
NEAR = 20  # 2% of the map, in the text's 0..1000 units
MAX_ID = 2**31 - 1


# ---------------------------------------------------------------------------
# Reading a SavedVariables file as data
# ---------------------------------------------------------------------------
class LuaData:
    """A parser for the table constructors WoW writes to SavedVariables.

    Accepts only literals (tables, strings, numbers, true/false/nil) and
    assignments of them to global names; anything else is an error.
    """

    TOKEN = re.compile(
        r"""\s*(?:
            (?P<long>--\[(?P<eq>=*)\[)
          | (?P<comment>--[^\n]*)
          | (?P<str>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')
          | (?P<num>-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?))
          | (?P<name>[A-Za-z_][A-Za-z_0-9]*)
          | (?P<sym>[{}\[\]=,;])
        )""",
        re.S | re.X,
    )
    MAX_DEPTH = 32

    def __init__(self, text):
        self.tokens = []
        pos = 0
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m or m.end() == pos:
                if text[pos:].strip() == "":
                    break
                raise ValueError(f"unexpected text at {pos}: {text[pos:pos + 20]!r}")
            pos = m.end()
            if m.group("long") is not None:
                # a long comment: find where it closes (once, no backtracking)
                end = text.find("]" + m.group("eq") + "]", pos)
                if end < 0:
                    raise ValueError("a comment that never ends")
                pos = end + len(m.group("eq")) + 2
                continue
            if m.group("comment") is not None:
                continue
            for kind in ("str", "num", "name", "sym"):
                if m.group(kind) is not None:
                    self.tokens.append((kind, m.group(kind)))
                    break
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise ValueError(f"expected {value!r}, got {tok[1]!r}")
        self.i += 1
        return tok

    @staticmethod
    def unquote(s):
        body = s[1:-1]
        out, i = [], 0
        escapes = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
        while i < len(body):
            c = body[i]
            if c == "\\" and i + 1 < len(body):
                n = body[i + 1]
                if n.isdigit():
                    digits = re.match(r"\d{1,3}", body[i + 1:]).group(0)
                    code = int(digits)
                    out.append(chr(code) if code < 128 else "")
                    i += 1 + len(digits)
                    continue
                out.append(escapes.get(n, n))
                i += 2
                continue
            out.append(c)
            i += 1
        return "".join(out)

    def value(self, depth=0):
        if depth > self.MAX_DEPTH:
            raise ValueError("tables nested too deeply")
        kind, tok = self.take()
        if kind == "str":
            return self.unquote(tok)
        if kind == "num":
            return float.fromhex(tok) if tok.lower().startswith(("0x", "-0x")) else (float(tok) if re.search(r"[.eE]", tok) else int(tok))
        if kind == "name" and tok in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[tok]
        if tok == "{":
            return self.table(depth + 1)
        raise ValueError(f"unexpected {tok!r}")

    def table(self, depth):
        t, n = {}, 1
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value(depth)
                self.take("]")
                self.take("=")
                t[key] = self.value(depth)
            elif self.peek()[0] == "name" and self.i + 1 < len(self.tokens) and self.tokens[self.i + 1][1] == "=":
                key = self.take()[1]
                self.take("=")
                t[key] = self.value(depth)
            else:
                t[n] = self.value(depth)
                n += 1
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return t

    def globals(self):
        out = {}
        while self.i < len(self.tokens):
            kind, name = self.take()
            if kind != "name":
                raise ValueError(f"expected a name, got {name!r}")
            self.take("=")
            out[name] = self.value()
        return out


# ---------------------------------------------------------------------------
# Cleaning what players send
# ---------------------------------------------------------------------------
def clean(s, max_len=200):
    if not isinstance(s, str):
        return ""
    s = re.sub(r"[\x00-\x1f\x7f\x85\u2028\u2029]", " ", s)
    s = re.sub(r"\|c[0-9a-fA-F]{8}", "", s).replace("|r", "")
    s = re.sub(r"\|H.*?\|h(.*?)\|h", r"\1", s)
    s = re.sub(r"\|[TA].*?\|[ta]", "", s)
    s = s.replace("|", "").strip()
    return s[:max_len]


def int_id(v):
    """A whole number from 1 to 2^31 - 1 (ids, map ids, levels), or None."""
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        n = v
    elif isinstance(v, float) and v.is_integer():
        n = int(v)
    elif isinstance(v, str) and re.fullmatch(r"\d{1,10}", v.strip()):
        n = int(v)
    else:
        return None
    return n if 1 <= n <= MAX_ID else None


def spot_units(v):
    """A map position 0..1 -> 0..1000, or None."""
    if isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 1:
        return int(v * 1000 + 0.5)
    return None


# ---------------------------------------------------------------------------
# A saved file -> the shared text format (what Learn.Export(true) writes)
# ---------------------------------------------------------------------------
def spots_text(spots):
    parts = []
    for m, lst in sorted(spots.items()):
        if lst:
            parts.append(f"{m}:" + ",".join(f"{x},{y}" for x, y in lst))
    return ";".join(parts)


def saved_spots(t):
    out = {}
    if not isinstance(t, dict):
        return out
    for m, lst in t.items():
        m = int_id(m)
        if m is None or not isinstance(lst, dict) or len(out) >= MAX_MAPS:
            continue
        nums = [lst.get(i) for i in range(1, 2 * MAX_SPOTS + 1)]
        pts = []
        for i in range(0, len(nums) - 1, 2):
            x, y = spot_units(nums[i]), spot_units(nums[i + 1])
            if x is not None and y is not None:
                pts.append((x, y))
        if pts:
            out[m] = pts
    return out


def refs(t, pattern, limit):
    out = []
    if isinstance(t, dict):
        for k in t:
            if isinstance(k, str) and re.fullmatch(pattern, k) and int_id(k[1:]) and len(out) < limit:
                out.append(k)
    return sorted(out)


def saved_to_text(path, locale=None):
    data = LuaData(Path(path).read_text(encoding="utf-8", errors="replace")).globals()
    db = data.get("WaypointTrackerDB")
    learned = db.get("learned") if isinstance(db, dict) else None
    if not isinstance(learned, dict):
        return "WTL1\tunknown\t0"
    titles = db.get("questTitles")
    loc = locale or (titles.get("locale") if isinstance(titles, dict) and isinstance(titles.get("locale"), str) else "unknown")
    lines = [f"WTL1\t{clean(loc, 8)}\tsaved"]

    def table(name):
        t = learned.get(name)
        return {int_id(k): v for k, v in t.items() if int_id(k) and isinstance(v, dict)} if isinstance(t, dict) else {}

    for i, e in sorted(table("npcs").items()):
        hostile = e.get("hostile")
        level = int_id(e.get("level"))
        services = sorted(s for s in (e.get("services") or {}) if isinstance(s, str) and re.fullmatch(r"[a-z_]{1,20}", s))
        fac = e.get("fac") if e.get("fac") in ("A", "H") else ""
        lines.append("\t".join(["N", str(i), clean(e.get("name")), "" if hostile is None else ("1" if hostile else "0"),
                                str(level or ""), ",".join(services), spots_text(saved_spots(e.get("spots"))), fac, clean(e.get("title"), 60)]))
    for i, e in sorted(table("objects").items()):
        lines.append("\t".join(["O", str(i), clean(e.get("name")), spots_text(saved_spots(e.get("spots")))]))
    for i, q in sorted(table("quests").items()):
        area = ""
        a = q.get("area")
        if isinstance(a, dict) and int_id(a.get(1)) and spot_units(a.get(2)) is not None and spot_units(a.get(3)) is not None:
            area = f"{int_id(a.get(1))}:{spot_units(a.get(2))},{spot_units(a.get(3))}"
        giver = ",".join(re.findall(r"[UO]\d+", q.get("giver") or "")) if isinstance(q.get("giver"), str) else ""
        ender = ",".join(re.findall(r"[UO]\d+", q.get("ender") or "")) if isinstance(q.get("ender"), str) else ""
        objs = q.get("objs") if isinstance(q.get("objs"), dict) else {}
        objs = "|".join(clean(objs[k]) for k in sorted(k for k in objs if isinstance(k, int))[:10] if clean(objs[k]))
        lines.append("\t".join(["Q", str(i), clean(q.get("title")), str(int_id(q.get("level")) or ""), giver, ender, area,
                                clean(q.get("text"), 1000), objs]))
    for i, it in sorted(table("items").items()):
        drops, sold = refs(it.get("from"), r"[UO]\d+", MAX_DROPS), refs(it.get("sold"), r"U\d+", MAX_SELLERS)
        if drops or sold:
            lines.append("\t".join(["I", str(i), clean(it.get("name")), ",".join(drops), ",".join(sold)]))
    mail = learned.get("mailboxes")
    if isinstance(mail, dict) and isinstance(mail.get("spots"), dict):
        lines.append("M\t" + spots_text(saved_spots(mail["spots"])))
    # the player's own corrections (not ones they imported)

    def fix_spot(p):
        if isinstance(p, dict) and int_id(p.get(1)) and spot_units(p.get(2)) is not None and spot_units(p.get(3)) is not None:
            return f"{int_id(p.get(1))}:{spot_units(p.get(2))},{spot_units(p.get(3))}"
        return ""
    fixes = learned.get("fixes")
    for key, lst in sorted(fixes.items() if isinstance(fixes, dict) else [], key=lambda kv: str(kv[0])):
        m = re.fullmatch(r"([NO])([0-9]{1,10})", key) if isinstance(key, str) else None
        if not m or not isinstance(lst, dict):
            continue
        for i in sorted(k for k in lst if isinstance(k, int))[:5]:
            fix = lst[i]
            if isinstance(fix, dict) and not fix.get("shared"):
                wrong, right = fix_spot(fix.get("wrong")), fix_spot(fix.get("right"))
                if wrong or right:
                    lines.append("\t".join(["C", m.group(1), m.group(2), wrong, right]))
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# What the shipped database already has
# ---------------------------------------------------------------------------
def lua_long(body, level=2):
    """body as a Lua long string, with a bracket level the text can't close
    (a name like "]==]" can never end the string and run as code)."""
    while "]" + "=" * level + "]" in body:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{body}\n]{eq}]"


def lua_block(text, name):
    m = re.search(name + r"\s*=\s*\[(=*)\[\n?(.*?)\]\1\]", text, re.S)
    return m.group(2) if m else ""


# maps WoW Forever reshaped: the classic spots there use the old shape
RESHAPED = {1412, 1423, 1433, 1453}


class Shipped:
    """The classic and curated data, to tell what a discovery adds."""

    def __init__(self):
        data = (DATA / "Data.lua").read_text(encoding="utf-8")
        # id -> {"fac": "A"/"H"/"AH"/"", "spots": {area: [(x, y), ...]}}
        self.classic = {"N": {}, "O": {}}
        for kind, block, fac_i, coord_i in (("N", "units", 2, 4), ("O", "objects", 1, 2)):
            for line in lua_block(data, block).split("\n"):
                f = line.split("\t")
                if f[0].isdigit():
                    spots = {}
                    parse_spots(f[coord_i] if len(f) > coord_i else "", spots)
                    self.classic[kind][int(f[0])] = {"fac": f[fac_i] if len(f) > fac_i else "", "spots": spots}
        self.classic_services = {}
        for line in lua_block(data, "services").split("\n"):
            f = line.split("\t")
            for ident in re.findall(r"(-?\d+):", f[1] if len(f) > 1 else ""):
                key = ("O", -int(ident)) if ident.startswith("-") else ("N", int(ident))
                self.classic_services.setdefault(key, set()).add(f[0])
        self.classic_drops, self.classic_sold = {}, {}
        for line in lua_block(data, "items").split("\n"):
            f = line.split("\t")
            if f[0].isdigit():
                i = int(f[0])
                self.classic_drops[i] = {"U" + n for n in re.findall(r"\d+", f[1] if len(f) > 1 else "")}
                self.classic_drops[i] |= {"O" + n for n in re.findall(r"\d+", f[2] if len(f) > 2 else "")}
                self.classic_sold[i] = {"U" + n for n in re.findall(r"\d+", f[3] if len(f) > 3 else "")}
        self.curated = {}
        load(lua_block((DATA / "Curated.lua").read_text(encoding="utf-8"), r"WaypointTrackerData\.curated"), self.curated, english=True)
        self.area_map = self._area_map()

    def _area_map(self):
        """Classic area number -> the game's map number, learned from the
        NPCs both databases place in one zone each."""
        votes = {}
        for ident, cl in self.classic["N"].items():
            cur = self.curated.get(("N", ident))
            if cur and len(cl["spots"]) == 1 and len(cur["spots"]) == 1:
                area, m = next(iter(cl["spots"])), next(iter(cur["spots"]))
                votes.setdefault(area, {}).setdefault(m, 0)
                votes[area][m] += 1
        out = {}
        for area, maps in votes.items():
            m, n = max(maps.items(), key=lambda kv: kv[1])
            if n >= 2 and n >= 0.8 * sum(maps.values()):
                out[area] = m
        return out

    def known_spots(self, key):
        """Every spot the shipped data has for this, per map."""
        known = {}
        cur = self.curated.get(key)
        for m, pts in (cur["spots"] if cur else {}).items():
            known.setdefault(m, []).extend(pts)
        cl = self.classic[key[0]].get(key[1])
        for area, pts in (cl["spots"] if cl else {}).items():
            m = self.area_map.get(area)
            if m and m not in RESHAPED:
                known.setdefault(m, []).extend(pts)
        return known

    def adds_something(self, key, e):
        """Does this discovery add to the classic + curated data?"""
        kind, ident = key
        f = e["fields"]
        cur = self.curated.get(key)
        cl = self.classic[kind].get(ident)
        if not cl and not cur:
            return True
        if cur and not cur["fields"][2] and f[2]:
            return True  # a name for a nameless curated one
        if kind == "N":
            cf = cur["fields"] if cur else []
            if len(f) > 8 and f[8] and not (len(cf) > 8 and cf[8]):
                return True  # a title
            have = set((cf[5] if len(cf) > 5 else "").split(",")) | self.classic_services.get(key, set())
            if any(s and s not in have for s in (f[5] if len(f) > 5 else "").split(",")):
                return True  # a service
            friendly = bool((cl or {}).get("fac") or (len(cf) > 7 and cf[7]))
            hostile = f[3] if len(f) > 3 else ""
            if (hostile == "1" and friendly) or (hostile == "0" and not friendly):
                return True  # friend or foe the other way round
        known = self.known_spots(key)
        for m, pts in e["spots"].items():
            here = known.get(m, [])
            for x, y in pts:
                if not any(abs(x - kx) <= NEAR and abs(y - ky) <= NEAR for kx, ky in here):
                    return True  # somewhere new
        return False

    def new_refs(self, ident, drops, sold):
        cur = self.curated.get(("I", ident), {})
        known_drops = self.classic_drops.get(ident, set()) | cur.get("from", set())
        known_sold = self.classic_sold.get(ident, set()) | cur.get("sold", set())
        return drops - known_drops, sold - known_sold


# ---------------------------------------------------------------------------
# Merging
# ---------------------------------------------------------------------------
def parse_spots(text, into):
    for m, nums in re.findall(r"(\d+):([\d,]+)", text or ""):
        m = int(m)
        if not 1 <= m <= MAX_ID or (m not in into and len(into) >= MAX_MAPS):
            continue
        vals = [int(v) for v in nums.split(",") if v]
        lst = into.setdefault(m, [])
        cells = {(x // 10, y // 10) for x, y in lst}
        for i in range(0, len(vals) - 1, 2):
            x, y = vals[i], vals[i + 1]
            if 0 <= x <= 1000 and 0 <= y <= 1000 and (x // 10, y // 10) not in cells and len(lst) < MAX_SPOTS:
                lst.append((x, y))
                cells.add((x // 10, y // 10))


# fields in the client's language: names/titles, and quest text
TEXT_FIELDS = {"N": {2, 8}, "O": {2}, "Q": {2, 7, 8}, "I": {2}}
# fields merged, not replaced (spots, drops, vendors)
LIST_FIELDS = {"N": {6}, "O": {3}, "Q": set(), "I": {3, 4}}
WIDTH = {"N": 9, "O": 4, "Q": 11, "I": 5}


# what every field that isn't text must look like; anything else is dropped
LIST = r"(?:{0}(?:,{0})*)?"
FIELD_PATTERNS = {
    "N": {3: r"[01]?", 4: r"[0-9]{0,3}", 5: LIST.format(r"[a-z_]{1,20}"), 6: r"[0-9:,;]*", 7: r"[AH]?"},
    "O": {3: r"[0-9:,;]*"},
    "Q": {3: r"[0-9]{0,3}", 4: LIST.format(r"[UO][0-9]{1,10}"), 5: LIST.format(r"[UO][0-9]{1,10}"),
          6: r"(?:[0-9]{1,10}:[0-9]{1,4},[0-9]{1,4})?", 9: LIST.format(r"[IUO][0-9]{1,10}"), 10: r"[AH]{0,2}"},
    "I": {3: LIST.format(r"[UO][0-9]{1,10}"), 4: LIST.format(r"U[0-9]{1,10}")},
}


def clean_field(kind, i, v):
    if i not in TEXT_FIELDS[kind]:
        pattern = FIELD_PATTERNS[kind].get(i)
        if pattern is None:
            return v if i < 2 else ""
        return v if re.fullmatch(pattern, v) else ""
    if kind == "Q" and i == 8:
        # quest objectives, one per "|"
        return "|".join(c for c in (clean(o) for o in v.split("|")[:10]) if c)
    return clean(v, 1000 if kind == "Q" and i == 7 else 60 if kind == "N" and i == 8 else 200)


def load(text, db, english=None):
    lines = text.split("\n")
    head = lines[0].split("\t") if lines else []
    if english is None:
        english = len(head) > 1 and head[1] in ("enUS", "enGB", "community")
    for line in lines[1:] if head and head[0] == "WTL1" else lines:
        f = line.rstrip("\r").split("\t")
        kind = f[0]
        if kind in WIDTH and len(f) > 1 and re.fullmatch(r"[0-9]{1,10}", f[1]) and 1 <= int(f[1]) <= MAX_ID:
            f = [clean_field(kind, i, v) for i, v in enumerate(f[:WIDTH[kind]])]
            key = (kind, int(f[1]))
            e = db.setdefault(key, {"fields": f[:], "spots": {}})
            old = e["fields"]
            # newer observations correct older ones
            for i, v in enumerate(f):
                if i >= len(old):
                    old.append(v)
                elif v and i not in LIST_FIELDS[kind] and (english or not old[i] or i not in TEXT_FIELDS[kind]):
                    old[i] = v
            if kind == "N":
                parse_spots(f[6] if len(f) > 6 else "", e["spots"])
            elif kind == "O":
                parse_spots(f[3] if len(f) > 3 else "", e["spots"])
            elif kind == "I":
                drops = e.setdefault("from", set())
                sold = e.setdefault("sold", set())
                for r in re.findall(r"[UO]\d+", f[3] if len(f) > 3 else ""):
                    if len(drops) < MAX_DROPS and int_id(r[1:]):
                        drops.add(r)
                for r in re.findall(r"U\d+", f[4] if len(f) > 4 else ""):
                    if len(sold) < MAX_SELLERS and int_id(r[1:]):
                        sold.add(r)
        elif kind == "M" and len(f) > 1:
            e = db.setdefault(("M", 0), {"fields": ["M"], "spots": {}})
            parse_spots(f[1] if re.fullmatch(r"[0-9:,;]*", f[1]) else "", e["spots"])
        elif kind == "C" and len(f) > 3:
            # a correction: N/O, id, the wrong spot, the right spot (either may
            # be empty, not both); a later one of the same wrong spot wins
            f = (f + [""])[:5]
            if f[1] in ("N", "O") and int_id(f[2]) and all(correction_spot(v) for v in f[3:5]) and (f[3] or f[4]):
                ident = f"{f[1]}{int(f[2])}|{f[3] or f[4]}"
                db[("C", ident)] = {"fields": ["C", f[1], str(int(f[2])), f[3], f[4]], "spots": {}}


def correction_spot(v):
    """True for "" or a valid "map:x,y" (x, y 0..1000)."""
    m = re.fullmatch(r"([0-9]{1,10}):([0-9]{1,4}),([0-9]{1,4})", v)
    return v == "" or bool(m and int_id(m.group(1)) and int(m.group(2)) <= 1000 and int(m.group(3)) <= 1000)


def dump(db, shipped):
    lines = ["WTL1\tcommunity\t1"]
    for (kind, ident), e in sorted(db.items()):
        if shipped and kind in ("N", "O") and not shipped.adds_something((kind, ident), e):
            continue
        f = (e["fields"] + [""] * WIDTH.get(kind, 2))[:WIDTH.get(kind, 2)]
        if kind == "N":
            f[6] = spots_text(e["spots"])
        elif kind == "O":
            f[3] = spots_text(e["spots"])
        elif kind == "I":
            drops, sold = e.get("from", set()), e.get("sold", set())
            if shipped:
                drops, sold = shipped.new_refs(ident, drops, sold)
            if not drops and not sold:
                continue
            f[3], f[4] = ",".join(sorted(drops)), ",".join(sorted(sold))
        elif kind == "M":
            f = ["M", spots_text(e["spots"])]
        elif kind == "C":
            f = e["fields"]
        lines.append("\t".join(str(v) for v in f).rstrip("\t"))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="shared text (.txt) or the addon's saved file (.lua)")
    ap.add_argument("--locale", help="the language of a saved file, when it can't tell (e.g. enUS)")
    ap.add_argument("--keep-known", action="store_true", help="keep what the shipped database already has")
    args = ap.parse_args()
    current = TARGET.read_text(encoding="utf-8")
    db = {}
    load(lua_block(current, r"WaypointTrackerData\.forever"), db)
    for path in args.files:
        if path.endswith(".lua"):
            text = saved_to_text(path, args.locale)
        else:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        before = len(db)
        load(text, db)
        print(f"{path}: {len(db) - before} new entries")
    shipped = None if args.keep_known else Shipped()
    body = dump(db, shipped)
    head = current[: re.search(r"WaypointTrackerData\.forever\s*=\s*", current).end()]
    out = head + lua_long(body) + "\n"
    # last line of defence: the file must hold exactly one string of data
    if out.count("WaypointTrackerData.forever =") != 1 or any(c in body for c in "\r\x00"):
        raise SystemExit("refusing to write: unexpected text in the merged data")
    TARGET.write_text(out, encoding="utf-8")
    print(f"{TARGET.relative_to(ROOT)}: {body.count(chr(10))} entries")


if __name__ == "__main__":
    main()
