#!/usr/bin/env python3
"""Pins the WoW Forever client rows Real routes' travel abilities rely on.

Reads full wago.tools DB2 CSV downloads from a cache directory and writes the
selected rows/columns to tools/fixtures/travel/<Table>-<build>-enUS.csv, which
tools/build_travel.py reads: the reagents and cast times of the class
teleports and hearthstones, and the item effects, cooldowns, charges, slots,
skill/level requirements and spell text of the reviewed teleport items in
tools/travel_items.tsv. It never downloads; fetch the tables first:

    for t in SpellReagents SpellMisc SpellCastTimes SpellName Spell SpellEffect \
             ItemXItemEffect ItemEffect ItemSparse PlayerCondition; do
      curl -o "$CACHE/$t.csv" "https://wago.tools/db2/$t/csv?build=$BUILD&locale=enUS"
    done

usage: tools/pin_travel_client.py CACHE BUILD [OUT_DIR]
Prints each output with the SHA-256 of its full source table and of the pinned
file, for tools/fixtures/manifest.json.
"""
import csv
import hashlib
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLES = {
    "SpellReagents": ["ID", "SpellID"] + ["Reagent_%d" % i for i in range(8)] + ["ReagentCount_%d" % i for i in range(8)],
    "SpellMisc": ["ID", "SpellID", "CastingTimeIndex"],
    "SpellCastTimes": ["ID", "Base"],
    "SpellName": ["ID", "Name_lang"],
    "Spell": ["ID", "Description_lang"],
    "SpellEffect": ["ID", "SpellID", "EffectIndex", "Effect", "ImplicitTarget_0", "ImplicitTarget_1", "EffectTriggerSpell"],
    "ItemXItemEffect": ["ID", "ItemEffectID", "ItemID"],
    "ItemEffect": ["ID", "TriggerType", "Charges", "CoolDownMSec", "CategoryCoolDownMSec", "SpellCategoryID", "SpellID",
                   "PlayerConditionID"],
    "ItemSparse": ["ID", "Display_lang", "Description_lang", "RequiredSkill", "RequiredSkillRank", "RequiredAbility",
                   "RequiredLevel", "InventoryType", "AllowableRace_0", "AllowableRace_1", "AllowableClass", "Bonding",
                   "MinFactionID", "MinReputation"],
    "PlayerCondition": ["ID", "Flags", "RaceMasks_0", "RaceMasks_1"],
}


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n").split("\t") for l in f if l.strip() and not l.startswith("#")]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cache, build = sys.argv[1], sys.argv[2]
    out_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, "fixtures", "travel")
    raw, rows = {}, {}
    for t in TABLES:
        path = os.path.join(cache, t + ".csv")
        raw[t] = open(path, "rb").read()
        rows[t] = list(csv.DictReader(io.StringIO(raw[t].decode("utf-8"))))
        missing = [c for c in TABLES[t] if c not in rows[t][0]]
        if missing:
            raise ValueError("%s lacks columns %s" % (t, missing))

    fixtures = os.path.join(HERE, "fixtures", "travel")
    spells = {int(f[1]) for f in read_tsv(os.path.join(fixtures, "mz_misc.tsv")) if f[0] == "teleport"}
    hearth_items = set()
    for f in read_tsv(os.path.join(fixtures, "mz_abilities.tsv")):
        if f[0] == "hearth":
            spells.add(int(f[2]))
            if f[1]:
                hearth_items.add(int(f[1]))
    items = {int(f[0]) for f in read_tsv(os.path.join(HERE, "travel_items.tsv"))} | hearth_items

    links = [r for r in rows["ItemXItemEffect"] if int(r["ItemID"]) in items]
    effect_ids = {int(r["ItemEffectID"]) for r in links}
    effects = [r for r in rows["ItemEffect"] if int(r["ID"]) in effect_ids]
    spells |= {int(r["SpellID"]) for r in effects}
    reagents = [r for r in rows["SpellReagents"] if int(r["SpellID"]) in spells]
    reagent_items = {int(r["Reagent_%d" % i]) for r in reagents for i in range(8) if int(r["Reagent_%d" % i] or 0)}
    misc = [r for r in rows["SpellMisc"] if int(r["SpellID"]) in spells]
    casts = {int(r["CastingTimeIndex"]) for r in misc}
    descs = [r for r in rows["Spell"] if int(r["ID"]) in spells]
    conds = {int(m) for r in descs for m in re.findall(r"\$\?pc(\d+)", r["Description_lang"] or "")}
    conds |= {int(r["PlayerConditionID"]) for r in effects if int(r["PlayerConditionID"] or 0)}
    keep = {
        "SpellReagents": reagents,
        "SpellMisc": misc,
        "SpellCastTimes": [r for r in rows["SpellCastTimes"] if int(r["ID"]) in casts],
        "SpellName": [r for r in rows["SpellName"] if int(r["ID"]) in spells],
        "Spell": descs,
        "SpellEffect": [r for r in rows["SpellEffect"] if int(r["SpellID"]) in spells],
        "ItemXItemEffect": links,
        "ItemEffect": effects,
        "ItemSparse": [r for r in rows["ItemSparse"] if int(r["ID"]) in items | reagent_items],
        "PlayerCondition": [r for r in rows["PlayerCondition"] if int(r["ID"]) in conds],
    }
    for t, cols in TABLES.items():
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\n")
        w.writerow(cols)
        for r in sorted(keep[t], key=lambda r: int(r["ID"])):
            w.writerow([r[c] for c in cols])
        data = buf.getvalue().encode("utf-8")
        name = "%s-%s-enUS.csv" % (t, build)
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(data)
        print("%s\t%d rows\tsource_sha256 %s\tsha256 %s" % (name, len(keep[t]), hashlib.sha256(raw[t]).hexdigest(),
                                                             hashlib.sha256(data).hexdigest()))


if __name__ == "__main__":
    main()
